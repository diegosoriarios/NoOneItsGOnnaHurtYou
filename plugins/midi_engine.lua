-- plugins/midi_engine.lua
-- Standard MIDI file parser + sample-based synthesizer, pure Lua, no libraries.
--
-- Architecture (why this sounds right):
--   * The sequencer clock is driven by SAMPLES GENERATED, never by dt
--     directly. Each frame dt is converted into a sample budget; audio is
--     emitted in fixed blocks and the song position advances exactly with
--     the audio queued, so notes can never drift from what you hear.
--   * Event times are precomputed in SECONDS by walking the file's tempo
--     map once at load. Mid-song tempo events are honored, and
--     tempoMultiplier is a clean, click-free scale on the clock.
--   * All instrument/drum samples are resampled + downmixed to mono 44100
--     Hz at load time, so pitch math is exact regardless of source files.
--   * Melodic voices are identified by (channel, note) so a note-off never
--     kills another track's note; drum hits are always unique voices.

local SAMPLE_RATE = 44100
local BLOCK_SIZE = 1024
local MAX_VOICES = 32

--------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------

local MIDIParser = {}

local function readBytes(data, pos, count)
  local value = 0
  for i = 0, count - 1 do
    value = value * 256 + data:byte(pos + i)
  end
  return value, pos + count
end

local function readVarLen(data, pos)
  local value = 0
  for _ = 1, 4 do
    local byte = data:byte(pos)
    if not byte then return value, pos end
    pos = pos + 1
    value = (value * 128) + (byte % 128)
    if byte < 128 then break end
  end
  return value, pos
end

function MIDIParser.parse(filename)
  local ok, file = pcall(love.filesystem.read, filename)
  if not ok or not file then
    print(("[midi_engine] Could not read '%s' (path must be relative to the game root, no leading slash)"):format(tostring(filename)))
    return nil
  end

  local pos = 1
  if file:sub(pos, pos + 3) ~= "MThd" then
    print(("[midi_engine] '%s' is not a Standard MIDI file"):format(tostring(filename)))
    return nil
  end
  pos = pos + 4

  local headerLen
  headerLen, pos = readBytes(file, pos, 4)

  local format, numTracks, division
  format, pos = readBytes(file, pos, 2)
  numTracks, pos = readBytes(file, pos, 2)
  division, pos = readBytes(file, pos, 2)
  pos = pos + (headerLen - 6)

  local tracks = {}
  local trackNames = {}
  local smpteTicksPerSecond = nil

  if division >= 0x8000 then
    local fps = 256 - math.floor(division / 256)
    local subframes = division % 256
    smpteTicksPerSecond = fps * subframes
  end

  for trackIndex = 1, numTracks do
    if pos + 8 > #file then break end
    local chunkId = file:sub(pos, pos + 3)
    pos = pos + 4
    local chunkLen
    chunkLen, pos = readBytes(file, pos, 4)
    if chunkId ~= "MTrk" then
      pos = pos + chunkLen
    else
      local track = {}
      local trackEnd = pos + chunkLen
      local time = 0
      local runningStatus = 0

      while pos < trackEnd do
        local delta
        delta, pos = readVarLen(file, pos)
        time = time + delta

        local status = file:byte(pos)
        if not status then break end

        if status < 0x80 then
          status = runningStatus
        else
          pos = pos + 1
          if status < 0xF0 then
            runningStatus = status
          end
        end

        local eventType = math.floor(status / 16)
        local channel = status % 16

        if eventType == 0x9 then
          local note = file:byte(pos)
          local velocity = file:byte(pos + 1)
          pos = pos + 2
          if velocity > 0 then
            track[#track + 1] = { type = "noteon", time = time, note = note, velocity = velocity, channel = channel }
          else
            track[#track + 1] = { type = "noteoff", time = time, note = note, channel = channel }
          end
        elseif eventType == 0x8 then
          local note = file:byte(pos)
          pos = pos + 2
          track[#track + 1] = { type = "noteoff", time = time, note = note, channel = channel }
        elseif eventType == 0xB then
          pos = pos + 2
        elseif eventType == 0xC then
          pos = pos + 1
        elseif eventType == 0xE then
          pos = pos + 2
        elseif eventType == 0xA then
          pos = pos + 2
        elseif eventType == 0xD then
          pos = pos + 1
        elseif eventType == 0xF then
          if status == 0xFF then
            local metaType = file:byte(pos)
            pos = pos + 1
            local length
            length, pos = readVarLen(file, pos)
            if metaType == 0x51 and length == 3 then
              local tempo
              tempo, pos = readBytes(file, pos, 3)
              track[#track + 1] = { type = "tempo", time = time, tempo = tempo }
            elseif metaType == 0x03 then
              trackNames[#tracks + 1] = file:sub(pos, pos + length - 1)
              pos = pos + length
            else
              pos = pos + length
            end
            runningStatus = 0
            if metaType == 0x2F then break end
          elseif status == 0xF0 or status == 0xF7 then
            local length
            length, pos = readVarLen(file, pos)
            pos = pos + length
            runningStatus = 0
          else
            break
          end
        else
          break
        end
      end

      tracks[#tracks + 1] = track
      pos = trackEnd
    end
  end

  return {
    tracks = tracks,
    trackNames = trackNames,
    division = division,
    format = format,
    smpteTicksPerSecond = smpteTicksPerSecond,
  }
end

--------------------------------------------------------------------
-- Synth
--------------------------------------------------------------------

local Synth = {}

function Synth.new(sampleRate)
  sampleRate = sampleRate or SAMPLE_RATE
  local self = {
    sampleRate = sampleRate,
    instruments = {},
    drumKit = {},
    voices = {},
    voiceCount = 0,
    voiceSeq = 0,
    masterGain = 0.6,
    delayBuf = {},
    delaySize = sampleRate * 2,
    delayWrite = 1,
    delaySamples = math.floor(sampleRate * 0.25),
    delayMix = 0,
    delayFeedback = 0.35,
    blockBuf = {},
    sendBuf = {},
  }

  local function addVoice(key, voice)
    if self.voices[key] == nil then
      while self.voiceCount >= MAX_VOICES do
        self.stealOldestVoice()
      end
      self.voiceCount = self.voiceCount + 1
    end
    self.voices[key] = voice
  end

  local function prepareSample(soundData)
    local srcRate = soundData:getSampleRate()
    local channels = soundData:getChannelCount()
    local total = soundData:getSampleCount()
    local frames = math.floor(total / channels)
    local ratio = srcRate / self.sampleRate
    local outFrames = math.max(1, math.floor(frames / ratio))

    local out = love.sound.newSoundData(outFrames, self.sampleRate, 16, 1)
    for i = 0, outFrames - 1 do
      local srcPos = i * ratio
      local i0 = math.floor(srcPos)
      local frac = srcPos - i0
      local i1 = math.min(i0 + 1, frames - 1)
      i0 = math.min(i0, frames - 1)
      local v0, v1 = 0, 0
      if channels == 1 then
        v0 = soundData:getSample(i0)
        v1 = soundData:getSample(i1)
      else
        local s0, s1 = 0, 0
        for c = 0, channels - 1 do
          s0 = s0 + soundData:getSample(i0 * channels + c)
          s1 = s1 + soundData:getSample(i1 * channels + c)
        end
        v0 = s0 / channels
        v1 = s1 / channels
      end
      out:setSample(i, v0 * (1 - frac) + v1 * frac)
    end
    return out
  end

  -- Sample files may be registered without an extension; try the common ones.
  local SAMPLE_EXTENSIONS = { ".wav", ".ogg", ".mp3" }

  local function resolveSamplePath(filename)
    if not love.filesystem.getInfo or love.filesystem.getInfo(filename) then
      return filename
    end
    local ext = filename:match("%.(%w+)$")
    local base = ext and filename:sub(1, -(#ext + 2)) or filename
    for _, candidate in ipairs(SAMPLE_EXTENSIONS) do
      local path = base .. candidate
      if love.filesystem.getInfo(path) then
        return path
      end
    end
    return nil
  end

  local function loadSample(filename)
    local path = resolveSamplePath(filename)
    if not path then
      return nil
    end
    local ok, sd = pcall(love.sound.newSoundData, path)
    if not ok or not sd then
      print(("[midi_engine] Failed to decode sample '%s' (%s). If this LÖVE build lacks MP3 support, convert samples to WAV/OGG.")
        :format(tostring(path), tostring(sd)))
      return nil
    end
    return prepareSample(sd)
  end

  function self.loadInstrument(id, filename)
    local sample = loadSample(filename)
    if sample then
      self.instruments[id] = sample
      return true
    end
    return false
  end

  function self.loadDrum(midiNote, filename)
    local sample = loadSample(filename)
    if sample then
      self.drumKit[midiNote] = sample
      return true
    end
    return false
  end

  function self.noteOn(note, velocity, channel, instrumentId, isDrum)
    local inst, key, pitch, loop, send
    if isDrum then
      inst = self.drumKit[note]
      if not inst then return end
      self.voiceSeq = self.voiceSeq + 1
      key = "d" .. self.voiceSeq
      pitch = 1.0
      loop = false
      send = 0.15
    else
      inst = self.instruments[instrumentId] or self.instruments[1]
      if not inst then return end
      key = "m" .. (channel or 0) .. ":" .. note
      pitch = 2 ^ ((note - 60) / 12)
      loop = true
      send = 0.3
    end
    addVoice(key, {
      inst = inst,
      pitch = pitch,
      gain = (velocity or 100) / 127,
      pointer = 0,
      loop = loop,
      send = send,
      seq = self.voiceSeq,
    })
  end

  function self.sfx(instrumentId, note, velocity, duration, isDrum)
    local inst, pitch, send
    if isDrum or instrumentId == nil then
      inst = self.drumKit[note]
      pitch = 1.0
      send = 0.15
    else
      inst = self.instruments[instrumentId]
      pitch = 2 ^ ((note - 60) / 12)
      send = 0.3
    end
    if not inst then return end
    self.voiceSeq = self.voiceSeq + 1
    addVoice("x" .. self.voiceSeq, {
      inst = inst,
      pitch = pitch,
      gain = (velocity or 100) / 127,
      pointer = 0,
      loop = true,
      send = send,
      age = 0,
      maxAge = math.floor((duration or 0.5) * self.sampleRate),
      seq = self.voiceSeq,
    })
  end

  function self.noteOff(note, channel)
    local key = "m" .. (channel or 0) .. ":" .. note
    if self.voices[key] then
      self.voices[key] = nil
      self.voiceCount = self.voiceCount - 1
    end
  end

  function self.allNotesOff()
    self.voices = {}
    self.voiceCount = 0
  end

  function self.stealOldestVoice()
    local oldestKey, oldestSeq
    for key, v in pairs(self.voices) do
      if not oldestSeq or v.seq < oldestSeq then
        oldestKey, oldestSeq = key, v.seq
      end
    end
    if oldestKey then
      self.voices[oldestKey] = nil
      self.voiceCount = self.voiceCount - 1
    end
  end

  function self.setDelayTime(seconds)
    local samples = math.floor(seconds * self.sampleRate)
    self.delaySamples = math.max(1, math.min(samples, self.delaySize - 1))
  end

  function self.generateSamples(count)
    local buf = self.delayBuf
    local size = self.delaySize
    local write = self.delayWrite
    local delaySamples = self.delaySamples
    local mix = self.delayMix
    local feedback = self.delayFeedback

    local dry = self.blockBuf
    local send = self.sendBuf
    for i = 1, count do
      dry[i] = 0
      send[i] = 0
    end

    for key, v in pairs(self.voices) do
      local inst = v.inst
      local sampleCount = inst:getSampleCount()
      local pointer = v.pointer
      local pitch = v.pitch
      local g = v.gain
      local s = v.send
      local getSample = inst.getSample
      local dead = false

      for i = 1, count do
        local fi = math.floor(pointer)
        if fi >= sampleCount then
          if v.loop then
            pointer = pointer - sampleCount
            fi = math.floor(pointer)
          else
            dead = true
            break
          end
        end
        local val = getSample(inst, fi) * g
        dry[i] = dry[i] + val
        send[i] = send[i] + val * s
        pointer = pointer + pitch
      end
      v.pointer = pointer

      if v.maxAge then
        v.age = v.age + count
        if v.age >= v.maxAge then dead = true end
      end
      if dead then
        self.voices[key] = nil
        self.voiceCount = self.voiceCount - 1
      end
    end

    local out = love.sound.newSoundData(count, self.sampleRate, 16, 1)
    local master = self.masterGain
    for i = 1, count do
      local readPos = write - delaySamples
      if readPos < 1 then readPos = readPos + size end
      local delayed = buf[readPos] or 0
      buf[write] = send[i] + delayed * feedback
      local sample = (dry[i] + delayed * mix) * master
      if sample > 1 then sample = 1 elseif sample < -1 then sample = -1 end
      out:setSample(i - 1, sample)
      write = write + 1
      if write > size then write = 1 end
    end
    self.delayWrite = write
    return out
  end

  return self
end

--------------------------------------------------------------------
-- Player
--------------------------------------------------------------------

local MIDIPlayer = {}

local function eventPriority(e)
  if e.type == "noteoff" then return 0 end
  if e.type == "tempo" then return 1 end
  if e.type == "noteon" then return 2 end
  return 3
end

function MIDIPlayer.new(midiData)
  local self = {
    midiData = midiData,
    synth = Synth.new(SAMPLE_RATE),
    sampleRate = SAMPLE_RATE,
    blockSize = BLOCK_SIZE,
    songPos = 0,
    pendingSamples = 0,
    tempoMultiplier = 1.0,
    playing = false,
    loop = true,
    eventQueue = {},
    eventIndex = 1,
    mutedTracks = {},
    trackInstruments = {},
    trackNames = {},
    currentTempo = 500000,
    loopLength = 0,
    tailSeconds = 1.5,
    lastBeatTime = 0,
    beatCount = 0,
    beatCallbacks = {},
    beatTimes = nil,
    beatsPerLoop = nil,
    latencyOffset = 0,
    delayBeats = 0.75,
    delayAuto = true,
    queueSource = nil,
  }

  if not midiData then return self end
  self.trackNames = midiData.trackNames or {}

  local events = {}
  local seq = 0
  for trackIndex, track in ipairs(midiData.tracks) do
    self.mutedTracks[trackIndex] = false
    for _, e in ipairs(track) do
      seq = seq + 1
      e.trackIndex = trackIndex
      e.seq = seq
      events[#events + 1] = e
    end
  end

  if midiData.smpteTicksPerSecond then
    local stps = midiData.smpteTicksPerSecond
    for _, e in ipairs(events) do
      e.timeSec = e.time / stps
    end
  else
    local tempoEvents = {}
    for _, e in ipairs(events) do
      if e.type == "tempo" then tempoEvents[#tempoEvents + 1] = e end
    end
    table.sort(tempoEvents, function(a, b) return a.time < b.time end)

    local division = math.max(1, midiData.division)
    local ti, curTick, curSec, curTempo = 1, 0, 0, 500000
    for _, e in ipairs(events) do
      while ti <= #tempoEvents and tempoEvents[ti].time <= e.time do
        local te = tempoEvents[ti]
        curSec = curSec + (te.time - curTick) * curTempo / (division * 1e6)
        curTick = te.time
        curTempo = te.tempo
        ti = ti + 1
      end
      e.timeSec = curSec + (e.time - curTick) * curTempo / (division * 1e6)
    end
  end

  table.sort(events, function(a, b)
    if a.timeSec ~= b.timeSec then return a.timeSec < b.timeSec end
    local pa, pb = eventPriority(a), eventPriority(b)
    if pa ~= pb then return pa < pb end
    return a.seq < b.seq
  end)
  self.eventQueue = events

  local lastSec = 0
  for _, e in ipairs(events) do
    if e.timeSec > lastSec then lastSec = e.timeSec end
  end
  self.loopLength = lastSec + self.tailSeconds

  function self.play()
    if not self.queueSource then
      self.queueSource = love.audio.newQueueableSource(self.sampleRate, 16, 1, 8)
      self.queueSource:setVolume(1.0)
      for _ = 1, 3 do
        self.queueSource:queue(self.advanceBlock())
      end
      self.queueSource:play()
    end
    self.playing = true
  end

  function self.pause()
    self.playing = false
  end

  function self.stop()
    self.playing = false
    self.songPos = 0
    self.eventIndex = 1
    self.lastBeatTime = 0
    self.pendingSamples = 0
    self.synth.allNotesOff()
  end

  function self.seek(seconds)
    seconds = math.max(0, math.min(seconds, self.loopLength))
    self.synth.allNotesOff()
    self.songPos = seconds

    local lo, hi = 1, #self.eventQueue
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      if self.eventQueue[mid].timeSec < seconds then
        lo = mid + 1
      else
        hi = mid - 1
      end
    end
    self.eventIndex = lo

    local baseBeat = self.currentTempo / 1e6
    self.lastBeatTime = math.floor(seconds / baseBeat) * baseBeat
  end

  function self.setTrackMuted(trackIndex, muted)
    self.mutedTracks[trackIndex] = muted and true or false
  end

  function self.toggleTrack(trackIndex)
    self.mutedTracks[trackIndex] = not self.mutedTracks[trackIndex]
  end

  function self.setTrackInstrument(trackIndex, instrumentId)
    self.trackInstruments[trackIndex] = instrumentId
  end

  function self.onBeat(callback)
    self.beatCallbacks[#self.beatCallbacks + 1] = callback
  end

  function self.sfx(instrumentId, note, velocity, duration)
    self.synth.sfx(instrumentId, note, velocity, duration)
  end

  function self.setDelay(mix, feedback, beats)
    self.synth.delayMix = mix or 0
    self.synth.delayFeedback = feedback or 0.35
    if beats then self.delayBeats = beats end
  end

  function self.getBeatDuration()
    return (self.currentTempo / 1e6) / math.max(0.05, self.tempoMultiplier)
  end

  function self.getBeatPhase()
    local baseBeat = self.currentTempo / 1e6
    if baseBeat <= 0 then return 0 end
    return ((self.songPos - self.lastBeatTime) / baseBeat) % 1
  end

  -- Song-time of every beat in the loop (walks the tempo map). Cached.
  function self.getBeatTimes()
    if self.beatTimes then return self.beatTimes end
    local times = {}
    local t = 0
    local beatDur = self.currentTempo / 1e6
    local i = 1
    local events = self.eventQueue
    while t < self.loopLength do
      times[#times + 1] = t
      t = t + beatDur
      while i <= #events do
        local e = events[i]
        if e.type == "tempo" then
          if e.timeSec <= t then
            beatDur = e.tempo / 1e6
            i = i + 1
          else
            break
          end
        else
          i = i + 1
        end
      end
    end
    self.beatTimes = times
    self.beatsPerLoop = #times
    return times
  end

  local function processEvents()
    local events = self.eventQueue
    while self.eventIndex <= #events do
      local e = events[self.eventIndex]
      if e.timeSec > self.songPos then break end
      self.eventIndex = self.eventIndex + 1

      if e.type == "tempo" then
        self.currentTempo = e.tempo
      elseif e.type == "noteon" then
        if not self.mutedTracks[e.trackIndex] then
          local isDrum = (e.channel == 9)
          local instId = self.trackInstruments[e.trackIndex] or 1
          self.synth.noteOn(e.note, e.velocity, e.channel, instId, isDrum)
        end
      elseif e.type == "noteoff" then
        self.synth.noteOff(e.note, e.channel)
      end
    end
  end

  local function processBeats()
    local baseBeat = self.currentTempo / 1e6
    while self.songPos + self.latencyOffset - self.lastBeatTime >= baseBeat do
      self.lastBeatTime = self.lastBeatTime + baseBeat
      self.beatCount = self.beatCount + 1
      for _, cb in ipairs(self.beatCallbacks) do
        cb(self.beatCount)
      end
    end
  end

  function self.advanceBlock()
    local blockSec = self.blockSize / self.sampleRate * math.max(0.05, self.tempoMultiplier)
    self.songPos = self.songPos + blockSec

    processEvents()
    processBeats()

    if self.songPos >= self.loopLength then
      if self.loop then
        self.songPos = self.songPos - self.loopLength
        self.eventIndex = 1
        self.lastBeatTime = 0
        self.synth.allNotesOff()
      else
        self.playing = false
      end
    end

    if self.delayAuto then
      self.synth.setDelayTime(self.getBeatDuration() * self.delayBeats)
    end

    return self.synth.generateSamples(self.blockSize)
  end

  function self.update(dt)
    if not self.playing then return end
    if not self.queueSource then self.play() end

    self.pendingSamples = self.pendingSamples + dt * self.sampleRate

    local queued = false
    while self.pendingSamples >= self.blockSize and self.playing do
      self.pendingSamples = self.pendingSamples - self.blockSize
      self.queueSource:queue(self.advanceBlock())
      queued = true
    end

    if queued and not self.queueSource:isPlaying() then
      self.queueSource:play()
    end
  end

  return self
end

return {
  Parser = MIDIParser,
  Player = MIDIPlayer,
  Synth = Synth,
  SAMPLE_RATE = SAMPLE_RATE,
}
