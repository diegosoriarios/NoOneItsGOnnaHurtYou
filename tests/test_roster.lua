-- tests/test_roster.lua
-- Headless verification of source/roster.lua: instrument registry, palette
-- resolution order, prefer lists, and track-name matching.
-- Run: luajit tests/test_roster.lua

package.path = "?.lua;" .. package.path

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
  if actual == expected then
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

local roster = require("source.roster")

-- Fake synth whose loaded instruments we control
local function fakeSynth(melodicLoaded, drumsLoaded)
  local instruments, drumKit = {}, {}
  for _, id in ipairs(melodicLoaded or {}) do instruments[id] = {} end
  for _, note in ipairs(drumsLoaded or {}) do drumKit[note] = {} end
  return { instruments = instruments, drumKit = drumKit }
end

-- Registry sanity
do
  assert_eq(#roster.ENTRIES, 11, "11 roster entries")
  local attacksSeen = {}
  for i, entry in ipairs(roster.ENTRIES) do
    assert_true(type(entry.attack) == "number", "entry " .. i .. " has attack index")
    assert_true(not attacksSeen[entry.attack], "attack " .. entry.attack .. " appears once")
    attacksSeen[entry.attack] = true
    assert_true(type(entry.instrument) == "string", "entry " .. i .. " has display name")
    assert_true(type(entry.sound) == "table", "entry " .. i .. " has a default sound")
  end
  for attack = 0, 10 do
    assert_true(attacksSeen[attack], "attack " .. attack .. " is in the roster")
  end
  assert_eq(roster.ENTRIES[1].attack, 0, "entry 1 is the drums/Circle starter")
end

-- instrumentSound: melodic and drum flavors
do
  local s = roster.instrumentSound("synth")
  assert_eq(s.inst, 2, "synth is melodic id 2")
  assert_eq(s.note, 60, "synth default note")
  assert_true(s.drum == nil, "synth is not a drum")

  local c = roster.instrumentSound("cowbell")
  assert_eq(c.inst, nil, "cowbell has no melodic id")
  assert_eq(c.note, 56, "cowbell is GM note 56")
  assert_eq(c.drum, true, "cowbell is a drum")

  assert_true(roster.instrumentSound("nope") == nil, "unknown instrument -> nil")
end

-- Resolution order: song palette > default palette > prefer > built-in
do
  local synth = fakeSynth({ 1, 2, 8 }, { 49, 52, 56, 57 })
  roster.PALETTES.default = { [9] = "cowbell" }
  roster.PALETTES["songs/song_a.mid"] = { [9] = "gong" }
  roster.PALETTES["songs/song_b.mid"] = { [9] = { instrument = "timpani", note = 50 } }
  roster.PALETTES["songs/song_c.mid"] = { [9] = { prefer = { "china", "crash" } } }
  roster.PALETTES["songs/song_d.mid"] = { [9] = "doesNotExist" }

  -- default palette applies everywhere...
  local def = roster.resolveAttackSound(9, "songs/other.mid", synth)
  assert_eq(def.note, 56, "default palette: cowbell")

  -- ...but the song palette wins
  local a = roster.resolveAttackSound(9, "songs/song_a.mid", synth)
  assert_eq(a.note, 52, "song palette: gong")

  -- explicit instrument + note override
  local b = roster.resolveAttackSound(9, "songs/song_b.mid", synth)
  assert_eq(b.inst, 8, "song palette: timpani melodic id")
  assert_eq(b.note, 50, "song palette note override")

  -- prefer list inside a song palette: first available wins
  local c = roster.resolveAttackSound(9, "songs/song_c.mid", synth)
  assert_eq(c.note, 57, "prefer: china loaded -> china")

  -- broken song-palette entry falls through to default palette
  local d = roster.resolveAttackSound(9, "songs/song_d.mid", synth)
  assert_eq(d.note, 56, "unknown instrument falls back to default palette")

  -- no palettes at all: entry prefer list (gong loaded)
  roster.PALETTES.default = {}
  local e = roster.resolveAttackSound(9, nil, synth)
  assert_eq(e.note, 52, "entry prefer: gong when loaded")

  -- prefer falls to second choice when gong missing
  local synthNoGong = fakeSynth({ 1, 8 }, { 49, 56 })
  local f = roster.resolveAttackSound(9, nil, synthNoGong)
  assert_eq(f.inst, 8, "entry prefer: timpani when gong missing")

  -- prefer exhausted -> built-in default sound (cowbell note 56)
  local synthBare = fakeSynth({ 1 }, { 49 })
  local g = roster.resolveAttackSound(9, nil, synthBare)
  assert_eq(g.note, 56, "prefer exhausted -> built-in default")
  assert_eq(g.drum, true, "built-in default is the drum cowbell")

  roster.PALETTES.default = {}
  roster.PALETTES["songs/song_a.mid"] = nil
  roster.PALETTES["songs/song_b.mid"] = nil
  roster.PALETTES["songs/song_c.mid"] = nil
  roster.PALETTES["songs/song_d.mid"] = nil
end

-- Track-name matching
do
  assert_eq(roster.instrumentIdForTrackName("Lead Guitar"), 4, "lead guitar by name")
  assert_eq(roster.instrumentIdForTrackName("rhythm gtr"), 3, "rhythm by name")
  assert_eq(roster.instrumentIdForTrackName("Synth Pad"), 2, "synth by name")
  assert_eq(roster.instrumentIdForTrackName("Bells"), 7, "bells by name")
  assert_eq(roster.instrumentIdForTrackName("Pista 1"), nil, "unrelated name -> nil")
  assert_eq(roster.instrumentIdForTrackName(nil), nil, "nil name -> nil")
end

-- Layer pairing: layer k pairs with entry k+1
do
  assert_eq(roster.entryMelodicId(2), 2, "layer 1 pairs with entry 2 (synth)")
  assert_eq(roster.entryMelodicId(3), 3, "layer 2 pairs with entry 3 (rhythm guitar)")
  assert_eq(roster.entryMelodicId(4), nil, "layer 3 (crash entry) has no melodic id")
  assert_eq(roster.entryMelodicId(6), 1, "layer 5 pairs with entry 6 (piano)")
end

-- collectNoteTimes: sorted, filterable
do
  local track = {
    { type = "noteon", timeSec = 1.5, note = 36 },
    { type = "noteon", timeSec = 0.5, note = 38 },
    { type = "noteoff", timeSec = 0.7, note = 36 },
    { type = "noteon", timeSec = 0.2, note = 36 },
    { type = "tempo", timeSec = 0.0, tempo = 500000 },
  }
  local all = roster.collectNoteTimes(track)
  assert_eq(#all, 3, "noteons collected")
  assert_true(all[1] < all[2] and all[2] < all[3], "times sorted ascending")
  local kicks = roster.collectNoteTimes(track, 36)
  assert_eq(#kicks, 2, "note filter applied")
  assert_eq(kicks[1], 0.2, "kick time")
end

-- buildHitBeats: beat slots with a note inside the window
do
  local beatTimes = { 0, 0.5, 1.0 }
  local noteTimes = { 0.49, 2.0 }
  local hits = roster.buildHitBeats(beatTimes, noteTimes, 0.06)
  assert_true(hits ~= nil, "hit map built")
  assert_true(hits[2], "beat 2 has the 0.49s hit (0.5 +- 0.06)")
  assert_true(not hits[1], "beat 1 has no hit")
  assert_true(not hits[3], "beat 3 has no hit")

  assert_true(roster.buildHitBeats(beatTimes, {}, 0.06) == nil, "no notes -> nil (ungated)")
  assert_true(roster.buildHitBeats(beatTimes, nil, 0.06) == nil, "nil notes -> nil")
  assert_true(roster.buildHitBeats(beatTimes, { 50.0 }, 0.06) == nil, "notes outside loop -> nil (ungated)")

  -- dense notes: two notes bracketing one beat still mark it once
  local dense = roster.buildHitBeats({ 0, 0.5 }, { 0.47, 0.53 }, 0.06)
  assert_true(dense[2], "bracketed beat marked")
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
print("ALL ROSTER TESTS PASSED")
