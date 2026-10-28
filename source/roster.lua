-- source/roster.lua
-- Single source of truth for the game's instrument/attack progression.
--
-- INSTRUMENTS: melodic samples (pitched by MIDI note). A missing file is not
--   an error: the synth falls back to instrument 1 (piano) until you drop the
--   sample into samples/.
-- DRUM_KIT: channel-10 one-shots (unpitched). Missing files stay silent.
-- ENTRIES: the unlock order. Entry 1 (Drums) is always on. Each entry pairs
--   an attack with an instrument; song layer k (melodic tracks in file order)
--   pairs with entry k+1.
-- PALETTES: per-song instrument overrides. Values are an instrument name
--   string, a table {instrument=, note=, vel=, dur=}, or a table
--   {prefer={...}} that picks the first available instrument.
--   Resolution order: song palette > default palette > entry prefer list >
--   entry's built-in sound.

local roster = {}

roster.INSTRUMENTS = {
  piano        = { melodic = 1, file = "samples/piano",        note = 48, vel = 105, dur = 0.6 },
  synth        = { melodic = 2, file = "samples/synth",        note = 60, vel = 110, dur = 0.5 },
  rhythmGuitar = { melodic = 3, file = "samples/rhythm_guitar", note = 40, vel = 115, dur = 0.3 },
  leadGuitar   = { melodic = 4, file = "samples/lead_guitar",  note = 72, vel = 110, dur = 0.5 },
  bass         = { melodic = 5, file = "samples/bass",         note = 36, vel = 115, dur = 0.4 },
  organ        = { melodic = 6, file = "samples/organ",        note = 53, vel = 105, dur = 0.7 },
  bells        = { melodic = 7, file = "samples/bells",        note = 76, vel = 100, dur = 0.8 },
  timpani      = { melodic = 8, file = "samples/timpani",      note = 48, vel = 120, dur = 0.8 },
}

roster.DRUM_KIT = {
  { note = 36, name = "kick",    file = "samples/kick" },
  { note = 38, name = "snare",   file = "samples/snare" },
  { note = 42, name = "hihat",   file = "samples/hihat" },
  { note = 49, name = "crash",   file = "samples/crash" },
  { note = 41, name = "tom",     file = "samples/tom" },
  { note = 52, name = "gong",    file = "samples/gong" },
  { note = 56, name = "cowbell", file = "samples/cowbell" },
  { note = 57, name = "china",   file = "samples/china" },
}

-- Display names for the drum kit instruments (used by palettes)
roster.DRUM_NAMES = {}
for _, d in ipairs(roster.DRUM_KIT) do
  roster.DRUM_NAMES[d.name] = d
end

-- Unlock order. attack = index into generateAttacks(). key = INSTRUMENTS/DRUM
-- registry key (nil for the drum kit entry, whose sound is its kit pieces).
roster.ENTRIES = {
  { attack = 0,  instrument = "Drums",         key = nil,           sound = { inst = nil, note = 36, vel = 127, drum = true } },
  { attack = 4,  instrument = "Synth",         key = "synth",       sound = { inst = 2,  note = 60, vel = 110, dur = 0.5 } },
  { attack = 5,  instrument = "Rhythm Guitar", key = "rhythmGuitar", sound = { inst = 3,  note = 40, vel = 115, dur = 0.3 } },
  { attack = 2,  instrument = "Crash",         key = "crash",       sound = { inst = nil, note = 49, vel = 127, drum = true } },
  { attack = 6,  instrument = "Lead Guitar",   key = "leadGuitar",  sound = { inst = 4,  note = 72, vel = 110, dur = 0.5 } },
  { attack = 7,  instrument = "Piano",         key = "piano",       sound = { inst = 1,  note = 48, vel = 105, dur = 0.6 } },
  { attack = 1,  instrument = "Bass",          key = "bass",        sound = { inst = 5,  note = 36, vel = 115, dur = 0.4 } },
  { attack = 3,  instrument = "Organ",         key = "organ",       sound = { inst = 6,  note = 53, vel = 105, dur = 0.7 } },
  { attack = 9,  instrument = "Gong",          key = "gong",        prefer = { "gong", "timpani", "cowbell" },
                                                sound = { inst = nil, note = 56, vel = 120, drum = true } },
  { attack = 8,  instrument = "Bells",         key = "bells",       sound = { inst = 7,  note = 76, vel = 100, dur = 0.8 } },
  { attack = 10, instrument = "Toms",          key = "tom",         sound = { inst = nil, note = 41, vel = 120, drum = true } },
}

-- Per-song instrument overrides, keyed by song path. See PALETTES doc above.
roster.PALETTES = {
  default = {},
  -- ["songs/your_metal_song.mid"] = {
  --   [9] = "gong",            -- Blood Arc plays the gong in this song
  --   [2] = { prefer = { "china", "crash" } },
  --   [6] = { instrument = "leadGuitar", note = 79 },  -- higher laser stab
  -- },
}

function roster.entryForAttack(attackIndex)
  for _, entry in ipairs(roster.ENTRIES) do
    if entry.attack == attackIndex then return entry end
  end
end

function roster.entryIndexForAttack(attackIndex)
  for i, entry in ipairs(roster.ENTRIES) do
    if entry.attack == attackIndex then return i end
  end
end

function roster.instrumentSound(name)
  local def = roster.INSTRUMENTS[name]
  if def then
    return { inst = def.melodic, note = def.note, vel = def.vel, dur = def.dur }
  end
  local drum = roster.DRUM_NAMES[name]
  if drum then
    return { inst = nil, note = drum.note, vel = 120, drum = true }
  end
  return nil
end

function roster.isAvailable(name, synth)
  local def = roster.INSTRUMENTS[name]
  if def then
    return synth.instruments[def.melodic] ~= nil
  end
  local drum = roster.DRUM_NAMES[name]
  if drum then
    return synth.drumKit[drum.note] ~= nil
  end
  return false
end

local function soundFromValue(value, synth)
  if type(value) == "string" then
    return roster.instrumentSound(value)
  elseif type(value) == "table" and value.prefer then
    for _, name in ipairs(value.prefer) do
      if roster.isAvailable(name, synth) then
        local s = roster.instrumentSound(name)
        if s then
          s.vel = value.vel or s.vel
          s.dur = value.dur or s.dur
          return s
        end
      end
    end
    return nil
  elseif type(value) == "table" and value.instrument then
    local s = roster.instrumentSound(value.instrument)
    if s then
      s.note = value.note or s.note
      s.vel = value.vel or s.vel
      s.dur = value.dur or s.dur
    end
    return s
  end
  return nil
end

-- Resolve the one-shot sound for an attack: song palette > default palette >
-- entry prefer list > entry built-in sound. Never returns a broken sound.
function roster.resolveAttackSound(attackIndex, songPath, synth)
  local songPalette = songPath and roster.PALETTES[songPath]
  if songPalette and songPalette[attackIndex] then
    local s = soundFromValue(songPalette[attackIndex], synth)
    if s then return s end
  end
  if roster.PALETTES.default and roster.PALETTES.default[attackIndex] then
    local s = soundFromValue(roster.PALETTES.default[attackIndex], synth)
    if s then return s end
  end
  local entry = roster.entryForAttack(attackIndex)
  if entry then
    if entry.prefer then
      local s = soundFromValue({ prefer = entry.prefer }, synth)
      if s then return s end
    end
    return entry.sound
  end
  return nil
end

-- Melodic instrument id for a roster entry (nil for drum-kit entries -> the
-- layer keeps the piano default until a real sample exists).
function roster.entryMelodicId(entryIndex)
  local entry = roster.ENTRIES[entryIndex]
  if not entry or not entry.key then return nil end
  local def = roster.INSTRUMENTS[entry.key]
  if def then return def.melodic end
  return nil
end

-- Match a MIDI track name to an instrument (e.g. "Lead Guitar" -> leadGuitar).
-- Falls back to nil if nothing matches.
function roster.instrumentIdForTrackName(trackName)
  if not trackName then return nil end
  local lowered = trackName:lower()
  local checks = {
    { keys = { "lead guitar", "lead" },           name = "leadGuitar" },
    { keys = { "rhythm guitar", "rhythm" },       name = "rhythmGuitar" },
    { keys = { "guitar" },                        name = "rhythmGuitar" },
    { keys = { "synth", "keys" },                 name = "synth" },
    { keys = { "bass" },                          name = "bass" },
    { keys = { "organ" },                         name = "organ" },
    { keys = { "bell", "chime" },                 name = "bells" },
    { keys = { "piano" },                         name = "piano" },
    { keys = { "timpani" },                       name = "timpani" },
  }
  for _, check in ipairs(checks) do
    for _, key in ipairs(check.keys) do
      if lowered:find(key, 1, true) then
        local def = roster.INSTRUMENTS[check.name]
        if def then return def.melodic end
      end
    end
  end
  return nil
end

-- Load every registered instrument/drum sample. Missing files are skipped
-- quietly by the engine (melodic voices fall back to piano).
function roster.loadInstruments(synth)
  for _, def in pairs(roster.INSTRUMENTS) do
    synth.loadInstrument(def.melodic, def.file)
  end
  for _, drum in ipairs(roster.DRUM_KIT) do
    synth.loadDrum(drum.note, drum.file)
  end
end

--------------------------------------------------------------------
-- Song gating: which beat slots actually contain a hit for an instrument
--------------------------------------------------------------------

-- Sorted song-times of a track's note-ons, optionally filtered by note number.
function roster.collectNoteTimes(track, noteFilter)
  local times = {}
  for _, e in ipairs(track or {}) do
    if e.type == "noteon" and (not noteFilter or e.note == noteFilter) then
      times[#times + 1] = e.timeSec or 0
    end
  end
  table.sort(times)
  return times
end

-- Map of beat index -> true for every beat with a note within `window`
-- seconds. Both arrays must be sorted ascending. Returns nil when there is
-- nothing to gate on (no notes) so the attack fires freely on its grid.
function roster.buildHitBeats(beatTimes, noteTimes, window)
  if not beatTimes or not noteTimes or #noteTimes == 0 then return nil end
  local hits = {}
  local j = 1
  for beatIndex = 1, #beatTimes do
    local t = beatTimes[beatIndex]
    while j <= #noteTimes and noteTimes[j] < t - window do
      j = j + 1
    end
    if j <= #noteTimes and noteTimes[j] <= t + window then
      hits[beatIndex] = true
    end
  end
  if next(hits) then return hits end
  return nil
end

return roster
