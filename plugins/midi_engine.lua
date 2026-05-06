-- main.lua - LÖVE2D MIDI Player (Fixed for LuaJIT/Lua 5.1)

local MIDIPlayer = {}

-- Helper function to read big-endian integers
local function readBytes(data, pos, count)
    local value = 0
    for i = 0, count - 1 do
        value = value * 256 + data:byte(pos + i)
    end
    return value, pos + count
end

-- Simple MIDI file parser
local MIDIParser = {}

function MIDIParser.readVarLen(data, pos)
    local value = 0
    local byte
    repeat
        byte = data:byte(pos)
        pos = pos + 1
        value = (value * 128) + (byte % 128)
    until byte < 128
    return value, pos
end

function MIDIParser.parse(filename)
    local file = love.filesystem.read(filename)
    if not file then return nil end
    
    local pos = 1
    local tracks = {}
    
    -- Read header chunk
    local header = file:sub(pos, pos + 3)
    if header ~= "MThd" then return nil end
    pos = pos + 4
    
    -- Header length (should be 6)
    local headerLen
    headerLen, pos = readBytes(file, pos, 4)
    
    -- Format, number of tracks, division
    local format, numTracks, division
    format, pos = readBytes(file, pos, 2)
    numTracks, pos = readBytes(file, pos, 2)
    division, pos = readBytes(file, pos, 2)
    
    -- Read tracks
    for i = 1, numTracks do
        local trackHeader = file:sub(pos, pos + 3)
        if trackHeader ~= "MTrk" then break end
        pos = pos + 4
        
        local trackLen
        trackLen, pos = readBytes(file, pos, 4)
        
        local track = {}
        local trackEnd = pos + trackLen
        local time = 0
        local runningStatus = 0
        
        while pos < trackEnd do
            -- Read delta time
            local delta
            delta, pos = MIDIParser.readVarLen(file, pos)
            time = time + delta
            
            -- Read event
            local status = file:byte(pos)
            
            if status < 0x80 then
                -- Running status
                status = runningStatus
            else
                pos = pos + 1
                runningStatus = status
            end
            
            local eventType = math.floor(status / 16)
            local channel = status % 16
            
            if eventType == 0x9 then -- Note On
                local note = file:byte(pos)
                local velocity = file:byte(pos + 1)
                pos = pos + 2
                
                if velocity > 0 then
                    table.insert(track, {type = "noteon", time = time, note = note, velocity = velocity, channel = channel})
                else
                    table.insert(track, {type = "noteoff", time = time, note = note, channel = channel})
                end
            elseif eventType == 0x8 then -- Note Off
                local note = file:byte(pos)
                pos = pos + 2
                table.insert(track, {type = "noteoff", time = time, note = note, channel = channel})
            elseif eventType == 0xB then -- Control Change
                pos = pos + 2
            elseif eventType == 0xC then -- Program Change
                pos = pos + 1
            elseif eventType == 0xE then -- Pitch Bend
                pos = pos + 2
            elseif eventType == 0xA then -- Aftertouch
                pos = pos + 2
            elseif eventType == 0xD then -- Channel Pressure
                pos = pos + 1
            elseif eventType == 0xF then -- System/Meta events
                if status == 0xFF then
                    local metaType = file:byte(pos)
                    pos = pos + 1
                    local length
                    length, pos = MIDIParser.readVarLen(file, pos)
                    
                    if metaType == 0x51 and length == 3 then -- Set Tempo
                        local tempo
                        tempo, pos = readBytes(file, pos, 3)
                        table.insert(track, {type = "tempo", time = time, tempo = tempo})
                    else
                        pos = pos + length
                    end
                elseif status == 0xF0 or status == 0xF7 then
                    local length
                    length, pos = MIDIParser.readVarLen(file, pos)
                    pos = pos + length
                end
            else
                -- Unknown event, skip 2 bytes
                if pos + 1 < trackEnd then
                    pos = pos + 2
                else
                    break
                end
            end
        end
        
        table.insert(tracks, track)
        pos = trackEnd
    end
    
    return {tracks = tracks, division = division, format = format}
end

-- Simple synthesizer
local Synth = {}

function Synth.new()
    local self = {
        activeNotes = {},
        sampleRate = 44100,
        instruments = {}, -- Store SoundData for each instrument
        drumKit = {} -- New table for drum samples
    }

    function self.loadInstrument(id, filename)
        local info = love.filesystem.getInfo(filename)
        if info then
            self.instruments[id] = love.sound.newSoundData(filename)
        end
    end

    function self.loadDrum(midiNote, filename)
        if love.filesystem.getInfo(filename) then
            self.drumKit[midiNote] = love.sound.newSoundData(filename)
        end
    end
    
    function self.noteOn(note, velocity, instrumentId, isDrum)
    if isDrum then
        local sample = self.drumKit[note]
        if sample then
            -- Drums don't pitch shift, they just play at pitch 1.0
            -- We use a unique key (note .. "drum" .. os.clock()) so multiple drums can overlap
            local drumKey = note .. "drum" .. os.clock()
            self.activeNotes[drumKey] = {
                inst = sample,
                pitch = 1.0, 
                velocity = velocity / 127,
                pointer = 0,
                loop = false -- Drums usually don't loop
            }
        end
    else
        local inst = self.instruments[instrumentId] or self.instruments[1] -- Fallback to 1
        if not inst then return end

        local pitch = math.pow(2, (note - 60) / 12)
        
        self.activeNotes[note] = {
            inst = inst,
            pitch = pitch,
            velocity = velocity / 127,
            pointer = 0,
            loop = true
        }
    end
end
    
    function self.noteOff(note)
        if self.activeNotes[note] then
        self.activeNotes[note] = nil
    end
    end
    
    function self.generateSamples(count)
    local samples = {}
    for i = 1, count do
        local out = 0
        local toRemove = {}
        
        for noteKey, data in pairs(self.activeNotes) do
            local inst = data.inst
            local sampleCount = inst:getSampleCount()
            
            -- Get the sample value at the current pointer
            local idx = math.floor(data.pointer)
            if idx < sampleCount then
                local s = inst:getSample(idx)
                out = out + s * data.velocity * 0.5
                
                -- Move pointer based on pitch
                data.pointer = data.pointer + data.pitch
                
                -- Loop the sample if it hits the end
                if data.pointer >= sampleCount then
                    if data.loop then
                        data.pointer = 0 
                    else
                        -- Mark for removal (drums)
                        table.insert(toRemove, noteKey)
                    end
                end
            else
                table.insert(toRemove, noteKey)
            end
        end
        
        -- Remove finished one-shot samples
        for _, key in ipairs(toRemove) do
            self.activeNotes[key] = nil
        end
        
        table.insert(samples, out)
    end
    return samples
end
    
    return self
end

-- MIDI Player
function MIDIPlayer.new(midiData)
    local self = {
        midiData = midiData,
        synth = Synth.new(),
        currentTime = 0,
        tempo = 500000, -- Default tempo (120 BPM)
        tempoMultiplier = 1.0, -- Add this line (1.0 is normal speed)
        playing = false,
        eventQueue = {},
        mutedTracks = {}, -- New table to store muted status (true = muted)
        queueSource = nil,
        eventIndex = 1 -- Initialize here to prevent nil errors in draw
    }
    
    -- Merge all tracks into one event queue
    for trackIndex, track in ipairs(midiData.tracks) do
        if trackIndex == 1 then
            self.mutedTracks[trackIndex] = false
        else
            self.mutedTracks[trackIndex] = true -- All tracks unmuted by default
        end
        
        for _, event in ipairs(track) do
            event.trackIndex = trackIndex -- Tag the event with its track ID
            table.insert(self.eventQueue, event)
        end
    end
    
    -- Sort by time
    table.sort(self.eventQueue, function(a, b) return a.time < b.time end)
    
    function self.play()
        if self.eventIndex > #self.eventQueue then
            self.eventIndex = 1
            self.currentTime = 0
        end
        self.playing = true
    end
    
    function self.pause()
        self.playing = false
    end
    
    function self.update(dt)
        if not self.playing then return end
        
        -- Convert delta time to MIDI ticks
        local ticksPerSecond = (1000000 / self.tempo) * self.midiData.division * self.tempoMultiplier
        self.currentTime = self.currentTime + dt * ticksPerSecond
        
        -- Process events
        while self.eventIndex <= #self.eventQueue do
            local event = self.eventQueue[self.eventIndex]
            
            if event.time > self.currentTime then
                break
            end
            
            local isMuted = self.mutedTracks[event.trackIndex]
            
            if event.type == "noteon" then
            if not isMuted then
                -- MIDI Channel 10 (index 9) is always drums
                local isDrum = (event.channel == 9)
                self.synth.noteOn(event.note, event.velocity, event.trackIndex, isDrum)
            end
            elseif event.type == "noteoff" then
                -- Always allow noteoff so notes don't get stuck
                self.synth.noteOff(event.note)
            elseif event.type == "tempo" then
                self.tempo = event.tempo
            end
            
            self.eventIndex = self.eventIndex + 1
        end
        
        -- Generate audio (1024 samples is about 23ms at 44.1kHz)
        -- We queue multiple buffers if needed to prevent gaps
        if not self.queueSource then
            -- 44100Hz, 16-bit, Mono, 8 buffers
            self.queueSource = love.audio.newQueueableSource(44100, 16, 1, 8)
            self.queueSource:setVolume(1.0) -- Ensure volume is max
            self.queueSource:play()
        end

        while self.queueSource:getFreeBufferCount() > 0 do
            local samples = self.synth.generateSamples(1024)
            local soundData = love.sound.newSoundData(#samples, 44100, 16, 1)
            for i = 1, #samples do
                -- Clamp samples to [-1, 1] to avoid distortion
                local s = math.max(-1, math.min(1, samples[i]))
                soundData:setSample(i - 1, s)
            end
            self.queueSource:queue(soundData)
        end
        
        -- Stop if finished
        if self.eventIndex > #self.eventQueue and #self.synth.activeNotes == 0 then
            self.playing = false
        end

        if not self.queueSource:isPlaying() and self.playing then
            self.queueSource:play()
        end
    end
    
    return self
end

-- LÖVE2D callbacks
local player = nil
local midiFile = nil

--[[function love.load()
    love.window.setTitle("LÖVE2D MIDI Player")
    love.window.setMode(800, 600)
    
    -- Try to load a MIDI file (you'll need to provide one)
    -- Place a MIDI file named "song.mid" in your project folder
    midiFile = MIDIParser.parse("song.mid")
    
    if midiFile then
        player = MIDIPlayer.new(midiFile)
    
    -- Load different sounds into the synth
        player.synth.loadInstrument(1, "samples/piano.mp3")
        --player.synth.loadInstrument(2, "strings.wav")
        --player.synth.loadInstrument(3, "flute.wav")

        player.synth.loadDrum(36, "samples/kick.mp3")
        player.synth.loadDrum(38, "samples/snare.mp3")
        player.synth.loadDrum(42, "samples/hihat.mp3")
        player.synth.loadDrum(49, "samples/crash.mp3")

        print("MIDI file loaded successfully!")
        print("Tracks: " .. #midiFile.tracks)
        print("Press SPACE to play/pause")
    else
        print("No MIDI file found. Place 'song.mid' in your project folder.")
    end
end

function love.update(dt)
    if player then
        player.update(dt)
    end
end

function love.draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("LÖVE2D MIDI Player", 20, 20)
    
    if player then
        -- Track Status UI
        love.graphics.print("Tracks (Press 1-9 to Mute):", 400, 20)
        for i = 1, math.min(9, #player.midiData.tracks) do
            local status = player.mutedTracks[i] and "MUTED" or "ON"
            local color = player.mutedTracks[i] and {1, 0, 0} or {0, 1, 0}
            love.graphics.setColor(color)
            love.graphics.print("Track " .. i .. ": " .. status, 400, 20 + (i * 20))
        end
        
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Press SPACE to play/pause", 20, 50)
        love.graphics.print("Speed: " .. math.floor(player.tempoMultiplier * 100) .. "% (U: Up, I: Down)", 20, 170)
        love.graphics.print("Status: " .. (player.playing and "Playing" or "Paused"), 20, 80)
        love.graphics.print("Time (Ticks): " .. string.format("%d", player.currentTime), 20, 110)
        love.graphics.print("Events: " .. player.eventIndex .. " / " .. #player.eventQueue, 20, 140)
        
        -- Visualizer: Draw active notes
        love.graphics.print("Active Notes:", 20, 180)
        local y = 200
        for noteKey, _ in pairs(player.synth.activeNotes) do
            -- Extract the numeric part of the key for the visualizer
            local noteNum = tonumber(noteKey) or tonumber(string.match(noteKey, "^(%d+)"))
            
            if noteNum then
                -- Draw a rectangle based on the MIDI note number
                love.graphics.rectangle("fill", 20, y, noteNum * 5, 10)
                y = y + 12
            end
            
            -- Limit drawing so it doesn't go off screen
            if y > 580 then break end
        end
    else
        love.graphics.print("No MIDI file loaded", 20, 50)
        love.graphics.print("Place 'song.mid' in your project folder", 20, 80)
    end
end

function love.keypressed(key)
local trackNum = tonumber(key)
    if trackNum and trackNum >= 1 and trackNum <= 9 and player then
        if player.midiData.tracks[trackNum] then
            player.mutedTracks[trackNum] = not player.mutedTracks[trackNum]
            
            -- If we just muted it, kill all active notes to be safe
            if player.mutedTracks[trackNum] then
                -- Optional: you could loop through active notes and clear them
                -- but the noteoff logic above usually handles this.
            end
        end
    end
  if key == "space" and player then
        if player.playing then player.pause() else player.play() end
    
    elseif key == "u" and player then
        -- Increase speed by 10%
        player.tempoMultiplier = player.tempoMultiplier + 0.1
        print("Speed: " .. math.floor(player.tempoMultiplier * 100) .. "%")
        
    elseif key == "i" and player then
        -- Decrease speed by 10% (clamp at 0.1 to prevent stopping/reversing)
        player.tempoMultiplier = math.max(0.1, player.tempoMultiplier - 0.1)
        print("Speed: " .. math.floor(player.tempoMultiplier * 100) .. "%")
        
    elseif key == "escape" then
        love.event.quit()
    end
end]]

return {
    Parser = MIDIParser,
    Player = MIDIPlayer
}