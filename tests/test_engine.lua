-- tests/test_engine.lua
-- Headless verification of plugins/midi_engine.lua (run: luajit tests/test_engine.lua)
-- Stubs the LÖVE API so the parser, sample-driven sequencer clock, voice
-- management, looping, and delay line can be tested without audio hardware.

package.path = "?.lua;" .. package.path

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
  if math.abs((actual or 0) - expected) < 1e-6 then
    passed = passed + 1
  else
    failed = failed + 1
    print(("FAIL: %s (expected %s, got %s)"):format(msg, tostring(expected), tostring(actual)))
  end
end

local function assert_true(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. tostring(msg))
  end
end

--------------------------------------------------------------------
-- LÖVE stubs
--------------------------------------------------------------------

local function bytes(t)
  local chars = {}
  for i, b in ipairs(t) do chars[i] = string.char(b) end
  return table.concat(chars)
end

local function varlen(n)
  local parts = { n % 128 }
  n = math.floor(n / 128)
  while n > 0 do
    table.insert(parts, 1, (n % 128) + 128)
    n = math.floor(n / 128)
  end
  return bytes(parts)
end

local function FakeSoundData(frames, rate, channels, fill)
  local data = {}
  for i = 0, frames * channels - 1 do
    data[i + 1] = fill and fill(i) or 0
  end
  return {
    getSampleCount = function() return frames * channels end,
    getSampleRate = function() return rate end,
    getChannelCount = function() return channels end,
    getDuration = function() return frames / rate end,
    getSample = function(_, i) return data[i + 1] or 0 end,
    setSample = function(_, i, v) data[i + 1] = v end,
    _data = data,
  }
end

love = {}

love.filesystem = {
  read = function(filename)
    local f = io.open(filename, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
  end,
  getInfo = function(filename)
    return {} -- pretend every sample file exists (newSoundData stub decodes anything)
  end,
}

love.sound = {
  newSoundData = function(a, b, c, d)
    if type(a) == "string" then
      -- pretend every sample file is 0.1s of 48kHz stereo sine
      return FakeSoundData(4800, 48000, 2, function(i) return 0.5 * math.sin(i * 0.05) end)
    end
    return FakeSoundData(a, b, d, nil)
  end,
}

local queuedBlocks = 0
love.audio = {
  newQueueableSource = function()
    return {
      queue = function() queuedBlocks = queuedBlocks + 1 end,
      play = function() end,
      isPlaying = function() return true end,
      getFreeBufferCount = function() return 8 end,
      setVolume = function() end,
    }
  end,
}

--------------------------------------------------------------------
-- MIDI file builder (synthetic test song)
--------------------------------------------------------------------

local function buildTestMidi()
  local trackEvents = {}
  local function ev(delta, ...) 
    trackEvents[#trackEvents + 1] = varlen(delta) .. bytes({ ... })
  end
  ev(0, 0x90, 60, 100)                                  -- t=0    noteon
  ev(240, 0x80, 60, 0)                                  -- t=240  noteoff
  ev(240, 0x90, 64, 100)                                -- t=480  noteon
  ev(240, 0x80, 64, 0)                                  -- t=720  noteoff
  ev(240, 0xFF, 0x51, 0x03, 0x03, 0xD0, 0x90)           -- t=960  tempo -> 250000
  ev(480, 0x90, 67, 100)                                -- t=1440 noteon
  ev(240, 0x80, 67, 0)                                  -- t=1680 noteoff
  ev(0, 0xFF, 0x2F, 0x00)                               -- end of track
  local trackData = table.concat(trackEvents)
  local track = bytes({ 0x4D, 0x54, 0x72, 0x6B })
    .. bytes({ 0, 0, math.floor(#trackData / 256) % 256, #trackData % 256 })
    .. trackData
  local header = bytes({ 0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0 })
  return header .. track
end

--------------------------------------------------------------------

local MIDI = require("plugins.midi_engine")

local function parseSynthetic()
  local oldRead = love.filesystem.read
  love.filesystem.read = function() return buildTestMidi() end
  local parsed = MIDI.Parser.parse("fake.mid")
  love.filesystem.read = oldRead
  return parsed
end

-- Parser: ticks -> seconds with a mid-song tempo change
do
  local parsed = parseSynthetic()

  assert_true(parsed ~= nil, "synthetic midi parses")
  assert_eq(#parsed.tracks, 1, "one track")
  assert_eq(parsed.division, 480, "division")

  local player = MIDI.Player.new(parsed)
  local times = {}
  for _, e in ipairs(player.eventQueue) do
    if e.type == "noteon" then times[#times + 1] = e.timeSec end
  end
  assert_eq(times[1], 0.0, "noteon 1 at 0s")
  assert_eq(times[2], 0.5, "noteon 2 at 0.5s")
  assert_eq(times[3], 1.25, "noteon 3 after tempo change at 1.25s")
  assert_eq(player.loopLength, 1.375 + player.tailSeconds, "loop length = last event + tail")
end

-- Sample-driven clock: songPos tracks real time (windowed: preroll excluded)
do
  local player = MIDI.Player.new(MIDI.Parser.parse("song.mid"))
  player.synth.loadInstrument(1, "fake.wav")
  player.play()
  for _ = 1, 30 do player.update(1 / 60) end
  local start = player.songPos
  for _ = 1, 60 do player.update(1 / 60) end
  local delta = player.songPos - start
  assert_true(math.abs(delta - 1.0) < 0.04, "1s real time -> ~1.0s song time, delta=" .. delta)
  assert_true(queuedBlocks > 0, "audio blocks were queued")
end

-- tempoMultiplier scales the song clock, not real time
do
  local player = MIDI.Player.new(MIDI.Parser.parse("song.mid"))
  player.synth.loadInstrument(1, "fake.wav")
  player.tempoMultiplier = 2.0
  player.play()
  for _ = 1, 30 do player.update(1 / 60) end
  local start = player.songPos
  for _ = 1, 60 do player.update(1 / 60) end
  local delta = player.songPos - start
  assert_true(math.abs(delta - 2.0) < 0.08, "2x multiplier: 1s real -> ~2.0s song, delta=" .. delta)
end

-- Seamless looping
do
  local player = MIDI.Player.new(parseSynthetic())
  player.synth.loadInstrument(1, "fake.wav")
  player.play()
  local wraps = 0
  local lastPos = 0
  for _ = 1, 400 do -- ~6.7s real, loop is 2.875s
    player.update(1 / 60)
    if player.songPos < lastPos - 0.01 then wraps = wraps + 1 end
    lastPos = player.songPos
  end
  assert_true(wraps >= 2, "song looped at least twice, wraps=" .. wraps)
  assert_true(player.songPos < player.loopLength, "songPos stayed within loop")
  assert_true(player.playing, "still playing after wraps")
end

-- Beat tracking at 120 BPM default tempo
do
  local player = MIDI.Player.new(parseSynthetic())
  local beats = {}
  player.onBeat(function(n) beats[#beats + 1] = n end)
  assert_true(math.abs(player.getBeatDuration() - 0.5) < 1e-6, "beat duration 0.5s at 120bpm")
  player.play()
  for _ = 1, 40 do player.update(1 / 60) end -- ~0.7s song time, before the tempo change at 1.0s
  assert_eq(#beats, 1, "exactly 1 beat fired by 0.7s at 120bpm")
  assert_true(player.getBeatPhase() >= 0 and player.getBeatPhase() < 1, "beat phase in [0,1)")
end

-- Voice management: drums overlap, noteoffs match channel
do
  local synth = MIDI.Synth.new(44100)
  synth.loadDrum(36, "fake.wav")
  synth.noteOn(36, 100, 9, nil, true)
  synth.noteOn(36, 100, 9, nil, true)
  assert_eq(synth.voiceCount, 2, "overlapping kicks are separate voices")

  synth.loadInstrument(1, "fake.wav")
  synth.noteOn(60, 100, 0, 1, false)
  synth.noteOn(60, 100, 1, 1, false)
  assert_eq(synth.voiceCount, 4, "same note on two channels = two voices")
  synth.noteOff(60, 0)
  assert_eq(synth.voiceCount, 3, "noteoff only kills its channel's voice")
  synth.allNotesOff()
  assert_eq(synth.voiceCount, 0, "allNotesOff")
end

-- Resampling: 48kHz stereo source -> 44.1kHz mono instrument
do
  local synth = MIDI.Synth.new(44100)
  synth.loadInstrument(1, "fake.wav")
  local inst = synth.instruments[1]
  assert_true(inst ~= nil, "instrument loaded")
  assert_eq(inst:getSampleRate(), 44100, "instrument resampled to 44100Hz")
  assert_eq(inst:getChannelCount(), 1, "instrument downmixed to mono")
  assert_eq(inst:getSampleCount(), 4410, "frame count scaled 48000->44100 (0.1s)")
end

-- Delay line produces bounded output
do
  local synth = MIDI.Synth.new(44100)
  synth.loadInstrument(1, "fake.wav")
  synth.delayMix = 0.5
  synth.delayFeedback = 0.4
  synth.setDelayTime(0.375)
  synth.noteOn(60, 127, 0, 1, false)
  local out = synth.generateSamples(4096)
  local ok = true
  for i = 0, out:getSampleCount() - 1 do
    local v = out:getSample(i)
    if v ~= v or v > 1 or v < -1 then ok = false break end
  end
  assert_true(ok, "delay output finite and within [-1,1]")
end

-- SFX voices auto-kill after their duration
do
  local synth = MIDI.Synth.new(44100)
  synth.loadInstrument(1, "fake.wav")
  synth.loadDrum(36, "fake.wav")
  synth.sfx(1, 60, 100, 0.1)
  assert_eq(synth.voiceCount, 1, "sfx voice created")
  synth.generateSamples(4096)
  assert_eq(synth.voiceCount, 1, "sfx alive before 0.1s")
  synth.generateSamples(4096)
  assert_eq(synth.voiceCount, 0, "sfx killed after 0.1s")

  synth.sfx(nil, 36, 127, 0.3)
  assert_eq(synth.voiceCount, 1, "drum sfx uses the drumKit")
  synth.sfx(nil, 42, 127, 0.3)
  assert_eq(synth.voiceCount, 1, "unknown drum note is ignored (no drumKit entry)")
  synth.sfx(2, 60, 100, 0.3)
  assert_eq(synth.voiceCount, 1, "unknown instrument id is ignored")
end

-- Muted tracks produce no voices
do
  local player = MIDI.Player.new(parseSynthetic())
  player.synth.loadInstrument(1, "fake.wav")
  player.setTrackMuted(1, true)
  player.play()
  for _ = 1, 30 do player.update(1 / 60) end
  assert_eq(player.synth.voiceCount, 0, "muted track never triggers voices")
end

-- Beat map: getBeatTimes walks the tempo map across the whole loop
do
  local player = MIDI.Player.new(parseSynthetic())
  local times = player.getBeatTimes()
  -- 120bpm to 1.0s, then 240bpm; loop = 1.375 + 1.5 tail = 2.875s
  assert_eq(#times, 10, "10 beats across the loop")
  assert_eq(player.beatsPerLoop, 10, "beatsPerLoop")
  assert_eq(times[1], 0, "first beat at 0")
  assert_eq(times[3], 1.0, "third beat at 1.0s (old tempo)")
  assert_eq(times[4], 1.25, "fourth beat at 1.25s (new tempo honored)")
  assert_eq(times[10], 2.75, "last beat inside the loop")
  assert_true(player.getBeatTimes() == times, "beat times are cached")
end

-- latencyOffset fires the beat clock early (visual calibration tool)
do
  local early = MIDI.Player.new(parseSynthetic())
  early.synth.loadInstrument(1, "fake.wav")
  early.latencyOffset = 0.5
  early.play()
  early.update(1 / 60)
  assert_true(early.beatCount >= 1, "offset 0.5s fires the first beat immediately")

  local ontime = MIDI.Player.new(parseSynthetic())
  ontime.synth.loadInstrument(1, "fake.wav")
  ontime.play()
  ontime.update(1 / 60)
  assert_eq(ontime.beatCount, 0, "zero offset: no beat yet at 0.07s song time")
end

-- Seek: repositions eventIndex, clears voices, clamps
do
  local player = MIDI.Player.new(parseSynthetic())
  player.synth.loadInstrument(1, "fake.wav")
  player.play()
  for _ = 1, 10 do player.update(1 / 60) end
  assert_true(player.synth.voiceCount > 0, "voices active before seek")

  player.seek(0.6)
  assert_eq(player.songPos, 0.6, "seek sets songPos")
  assert_eq(player.synth.voiceCount, 0, "seek clears voices")
  assert_eq(player.eventQueue[player.eventIndex].timeSec, 0.75, "eventIndex at first event >= seek")

  player.seek(999)
  assert_eq(player.songPos, player.loopLength, "seek clamps to loopLength")

  player.seek(0)
  assert_eq(player.eventIndex, 1, "seek(0) restarts events")

  local started = player.songPos
  for _ = 1, 40 do player.update(1 / 60) end
  assert_true(player.songPos > started + 0.5, "keeps playing after seek")
end

-- Real project songs parse and have sane timing
do
  for _, path in ipairs({ "song.mid", "songs/garota_do_cemiterio.mid" }) do
    local parsed = MIDI.Parser.parse(path)
    assert_true(parsed ~= nil, path .. " parses")
    if parsed then
      local player = MIDI.Player.new(parsed)
      local prev = -1
      local monotonic = true
      for _, e in ipairs(player.eventQueue) do
        if e.timeSec < prev then monotonic = false end
        prev = e.timeSec
      end
      assert_true(monotonic, path .. " event times are monotonically increasing")
      assert_true(player.loopLength > 1, path .. " has a positive song length (" ..
        string.format("%.1fs", player.loopLength) .. ")")
      print(("INFO: %s -> %d tracks, %d events, loop %.1fs, tempo changes honored"):format(
        path, #parsed.tracks, #player.eventQueue, player.loopLength))
    end
  end
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
print("ALL TESTS PASSED")
