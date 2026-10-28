-- main_midi.lua
-- Standalone MIDI harness: audition songs, layers and instrument mappings
-- without playing the game. Run from the repo root:
--   love . --midi
--
-- Keys:
--   space        play / pause
--   left/right   seek -/+ 5 seconds
--   u / i        tempo multiplier -/+ 10%
--   1..9         mute / unmute track N
--   l            toggle looping
--   d            cycle delay level (0-3, beat-synced echo)
--   g            toggle game layers (drums-only start, like the real game)
--   [ / ]        previous / next song in songs/
--   r            restart song
--   esc          quit
local MIDI = require("plugins.midi_engine")
local roster = require("source.roster")

local player
local songs = {}
local songIndex = 1
local gameLayers = false
local trackInfo = {}
local gateCoverage = {}
local delayLevel = 0

local function loadSongList()
  songs = {}
  if love.filesystem.getInfo("song.mid") then
    songs[#songs + 1] = "song.mid"
  end
  local items = love.filesystem.getDirectoryItems("songs")
  table.sort(items)
  for _, item in ipairs(items) do
    if item:sub(-4):lower() == ".mid" then
      songs[#songs + 1] = "songs/" .. item
    end
  end
end

local function applyGameLayers()
  if not player then return end
  for ti, info in ipairs(trackInfo) do
    if gameLayers then
      player.setTrackMuted(ti, info.notes > 0 and not info.hasDrums)
    else
      player.setTrackMuted(ti, false)
    end
  end
end

local function cycleDelay()
  delayLevel = (delayLevel + 1) % 4
  player.setDelay(0.22 * delayLevel, 0.3 + 0.08 * delayLevel, 0.75)
end

local function startSong(path)
  if player and player.queueSource then
    player.queueSource:stop()
  end

  local data = MIDI.Parser.parse(path)
  if not data then
    print("[harness] could not parse " .. tostring(path))
    return
  end

  player = MIDI.Player.new(data)
  roster.loadInstruments(player.synth)
  delayLevel = 0

  trackInfo = {}
  gateCoverage = {}
  local drumTrackIndex = nil
  for ti, track in ipairs(data.tracks) do
    local notes, hasDrums = 0, false
    local channels = {}
    for _, e in ipairs(track) do
      if e.type == "noteon" then
        notes = notes + 1
        channels[e.channel] = true
        if e.channel == 9 then hasDrums = true end
      end
    end
    if hasDrums and not drumTrackIndex then
      drumTrackIndex = ti
    end
    local channelList = {}
    for c in pairs(channels) do channelList[#channelList + 1] = c end
    table.sort(channelList)
    trackInfo[ti] = {
      notes = notes,
      hasDrums = hasDrums,
      channels = table.concat(channelList, ","),
      name = (data.trackNames and data.trackNames[ti]) or ("Track " .. ti),
    }
  end

  -- gate coverage per roster entry (beats with a hit / total beats)
  local beatTimes = player.getBeatTimes()
  local window = math.max(0.04, ((beatTimes[2] or beatTimes[1]) - (beatTimes[1] or 0)) / 8)
  for entryIndex, entry in ipairs(roster.ENTRIES) do
    local noteTimes
    local layerIndex = entryIndex - 1
    local layerTrack = nil
    local melodicSeen = 0
    for ti, track in ipairs(data.tracks) do
      local hasDrums = trackInfo[ti].hasDrums
      local hasNotes = trackInfo[ti].notes > 0
      if hasNotes and not hasDrums then
        melodicSeen = melodicSeen + 1
        if melodicSeen == layerIndex then layerTrack = ti end
      end
    end
    if layerTrack then
      noteTimes = roster.collectNoteTimes(data.tracks[layerTrack])
    elseif entry.sound and entry.sound.drum and drumTrackIndex then
      noteTimes = roster.collectNoteTimes(data.tracks[drumTrackIndex], entry.sound.note)
    end
    local hits = roster.buildHitBeats(beatTimes, noteTimes, window)
    if hits then
      local n = 0
      for _ in pairs(hits) do n = n + 1 end
      gateCoverage[entryIndex] = ("%d/%d beats"):format(n, #beatTimes)
    else
      gateCoverage[entryIndex] = "ungated"
    end
  end

  if gameLayers then applyGameLayers() end
  player.play()
end

function love.load()
  love.window.setTitle("MIDI Harness")
  love.window.setMode(860, 640)

  loadSongList()
  if #songs == 0 then
    songs[1] = nil
    print("[harness] no .mid files found (put one in songs/)")
    return
  end
  startSong(songs[songIndex])
end

function love.update(dt)
  if player then
    player.update(dt)
  end
end

function love.draw()
  love.graphics.setColor(1, 1, 1)
  if not player then
    love.graphics.print("No song loaded. Drop a .mid into songs/ and restart.", 20, 20)
    return
  end

  local songName = songs[songIndex] or "?"
  love.graphics.print(("MIDI Harness  -  %s  (%d/%d)"):format(songName, songIndex, #songs), 20, 20)
  love.graphics.print(("%.1fx tempo   %s   loop %s   delay %d/3   latency +%dms"):format(
    player.tempoMultiplier,
    player.playing and "PLAYING" or "PAUSED",
    player.loop and "on" or "off",
    delayLevel, math.floor(player.latencyOffset * 1000 + 0.5)), 20, 45)
  love.graphics.print(("%.1fs / %.1fs   beat %d   voices %d   game-layers %s"):format(
    player.songPos, player.loopLength, player.beatCount,
    player.synth.voiceCount, gameLayers and "on" or "off"), 20, 70)

  -- beat phase bar
  local phase = player.getBeatPhase()
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.rectangle('fill', 20, 100, 400, 8)
  love.graphics.setColor(0, 1, 0.4)
  love.graphics.rectangle('fill', 20, 100, 400 * phase, 8)

  -- song position bar
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.rectangle('fill', 20, 115, 400, 8)
  love.graphics.setColor(0.3, 0.6, 1)
  love.graphics.rectangle('fill', 20, 115, 400 * (player.songPos / math.max(0.001, player.loopLength)), 8)

  -- tracks
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Tracks (1-9 mute; ch column shows MIDI channels):", 20, 140)
  local y = 165
  for ti, info in ipairs(trackInfo) do
    if ti > 9 then break end
    local muted = player.mutedTracks[ti]
    local label = ("[%d] %-18s ch:%-6s notes:%-5d %s"):format(
      ti, info.name:sub(1, 18), info.channels, info.notes,
      info.hasDrums and "(drums)" or "")
    if muted then
      love.graphics.setColor(1, 0.3, 0.3)
    else
      love.graphics.setColor(0.5, 1, 0.5)
    end
    love.graphics.print(label .. (muted and "  MUTED" or "  on"), 20, y)
    y = y + 20
  end

  -- roster gate coverage
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Attack gating (fires only on these song beats):", 20, y + 10)
  y = y + 30
  for entryIndex, entry in ipairs(roster.ENTRIES) do
    if entryIndex > 6 then break end
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print(("%-14s %s"):format(entry.instrument, gateCoverage[entryIndex] or "-"), 20, y)
    y = y + 18
  end

  love.graphics.setColor(0.7, 0.7, 0.7)
  love.graphics.print("space play   left/right seek 5s   u/i tempo   -/= latency   l loop", 20, love.graphics.getHeight() - 95)
  love.graphics.print("d delay   g game-layers   [ ] song   r restart   1-9 mute   esc quit", 20, love.graphics.getHeight() - 75)
end

function love.keypressed(key)
  if not player then
    if key == "escape" then love.event.quit() end
    return
  end

  local trackNum = tonumber(key)
  if trackNum and trackNum >= 1 and trackNum <= 9 and player.midiData.tracks[trackNum] then
    player.toggleTrack(trackNum)
  elseif key == "space" then
    if player.playing then player.pause() else player.play() end
  elseif key == "right" then
    player.seek(player.songPos + 5)
  elseif key == "left" then
    player.seek(player.songPos - 5)
  elseif key == "u" then
    player.tempoMultiplier = math.min(3, player.tempoMultiplier + 0.1)
  elseif key == "i" then
    player.tempoMultiplier = math.max(0.5, player.tempoMultiplier - 0.1)
  elseif key == "=" then
    player.latencyOffset = player.latencyOffset + 0.01
  elseif key == "-" then
    player.latencyOffset = math.max(0, player.latencyOffset - 0.01)
  elseif key == "l" then
    player.loop = not player.loop
  elseif key == "d" then
    cycleDelay()
  elseif key == "g" then
    gameLayers = not gameLayers
    applyGameLayers()
  elseif key == "r" then
    player.stop()
    player.play()
  elseif key == "[" or key == "]" then
    if #songs > 0 then
      if key == "]" then
        songIndex = songIndex % #songs + 1
      else
        songIndex = (songIndex - 2) % #songs + 1
      end
      startSong(songs[songIndex])
    end
  elseif key == "escape" then
    love.event.quit()
  end
end
