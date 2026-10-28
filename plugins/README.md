# MIDI Engine — integration guide

`plugins/midi_engine.lua` is a from-scratch Standard MIDI File parser and
sample-based synthesizer in pure Lua (no libraries). It powers the game's
soundtrack, the beat-locked attacks, and the music upgrades. This doc explains
how it works and exactly how this game wires it in, so you can maintain,
re-wire or extend it yourself.

## Architecture in 60 seconds

Two signal paths share **one clock**:

```
                AUDIO PATH
  song.mid ──> Parser ──> event queue (times in SECONDS)
                            │
                            v
                 Player sample-driven clock
                 (position advances with audio
                  generated, never with dt)
                            │
                            v
        Synth voices ──> 44100 Hz mono stream ──> speakers
        (samples auto-resampled/downmixed at load)

                GAMEPLAY PATH
        Player beat grid (beatCount, getBeatPhase)
                            │
                            v
        attack.beatDue() ──> attack fires on the beat
                            │
                            v
        player.sfx(...) ──> one-shot voice into the SAME synth
```

The golden rule: every event, beat and note is scheduled against the number of
audio samples already generated. `dt` only tops up the sample budget. That is
why notes can never drift from what you hear, and why changing
`tempoMultiplier` is click-free.

A second consequence: **`music.update(dt)` must run every frame**, even when
gameplay is paused. Skipping it starves the audio queue and the music
stutters.

## The wiring in this game, file by file

### 1. Load and start — `source/screens/game.lua:85-140`

```lua
local roster = require("source.roster")            -- top of file

currentSongPath = "songs/garota_do_cemiterio.mid"
local data = MIDI.Parser.parse(currentSongPath)
assert(data, "midi_engine: could not parse '" .. currentSongPath .. "'")
music = MIDI.Player.new(data)                      -- global: attacks/upgrades use it

roster.loadInstruments(music.synth)                -- every registered sample
```

Then the layer auto-detection: any track that has notes but **no** channel-10
(0-indexed 9) events is a melodic layer. Layers start muted and get their
instrument from the track name (DAW naming) or the roster pairing (layer *k*
pairs with roster entry *k+1*). Unlock state lives in `music.unlockedRoster` /
`layer.unlocked`; the character's starter entry is unlocked in
`game:init` (`game.lua:140-153`) before `music.play()`, so your instrument
audibly joins the drums from the first beat.

### 2. The heartbeat — `source/screens/game.lua:135`

```lua
function game:update(dt)
  music.update(dt)          -- ALWAYS first
  if showUpgradeMenu then return end
  ...
```

`music.update(dt)` converts `dt` into audio blocks, fires due events, advances
the beat grid and queues samples. Because it runs *before* the upgrade-menu
early return, the song keeps playing (and looping) while the player picks
upgrades. Gameplay code below it is what pauses.

### 3. The sync contract — `source/attacks.lua`

Four local helpers turn the music clock into attack behavior:

| Helper | Role |
|---|---|
| `attackPeriod(self)` | seconds between fires = `beatDiv * music:getBeatDuration()` (drives cooldown bars) |
| `alignNextBeat(self, beat)` | next beat matching this attack's `beatDiv`/`beatOffset` pattern |
| `beatDue(self, dt)` | true exactly once per matching beat — **and only if the song actually plays a hit there** (song gating below); skips beats missed during pauses; falls back to a 1 s timer if `music` is nil |
| `playAttackSound(self)` | plays `self.sound` through `music.sfx` |

**Song gating** — attacks follow the music instead of a blind metronome. At
`game:init`, each roster entry gets a `hitBeats` map built from the song:
its paired layer's notes (layer *k* ↔ entry *k+1*), or — for drum-kit
attacks — the specific kit note inside the channel-10 track (Circle → kicks,
Crash → crash hits). `beatDue` then fires only on slots where the song has a
hit (±⅛ beat). Song rests = attack rests; a gong attack literally follows the
gong line. `music:getBeatTimes()` / `music.beatsPerLoop` (engine) provide the
beat grid; `roster.buildHitBeats()` builds the maps; set
`songGatingEnabled = false` for the pure metronome. If the song has no source
for an entry (no such layer/kit note), that attack is ungated and fires on
its grid. `music.latencyOffset` (seconds, default 0, tune live with `-`/`=`
in the harness) shifts the beat clock early if your audio device latency
makes visuals feel ahead.

Each attack declares three fields and nothing else:

```lua
beatDiv    = 1,     -- fire every N beats
beatOffset = 1,     -- shift inside the pattern (offbeats), optional
sound      = { inst = nil, note = 36, vel = 127, drum = true },
```

The current arrangement — `source/roster.lua` is the single source of truth:

| Unlock order | Attack | Instrument | Pattern |
|---|---|---|---|
| starter | Circle | Drums (kick) | every beat |
| 2 | Fire Tower | Synth stab | beat 2 of bar |
| 3 | Bouncing Knife | Rhythm guitar chunk | offbeat |
| 4 | Random Circle | Crash | offbeat |
| 5 | Laser Beam | Lead guitar | once per bar |
| 6 | V-Wall | Piano | beat 2 of bar |
| 7 | Radial | Bass | every 2 beats |
| 8 | Boomerang | Organ | once per bar |
| 9 | Blood Arc | Gong (or timpani/cowbell — `prefer` list) | every 2 beats |
| 10 | Poison | Bells | beat 3 of bar |
| 11 | Flame Thrower | Toms | every 2 beats |

### 4. Music as roguelite state — `source/upgrades.lua`

Upgrades mutate the *same* player object; `canOffer()` predicates let
`getRandomUpgrades` filter the pool dynamically. Two families:

**Instrument upgrades** — one per roster entry, **free choice, any order**:
`Add Drums`, `Add Synth`, `Add Rhythm Guitar`, `Add Crash`, `Add Lead
Guitar`, `Add Piano`, `Add Bass`, `Add Organ`, `Add Gong`, `Add Bells`,
`Add Toms`. Each unlock brings exactly ONE instrument: its attack plus the
song layer paired with it (entry *k* ↔ layer *k−1*). Entry 1 is **Drums**:
it adds the Circle attack and unmutes the drum track, so for non-Drummer
characters the drums are their own unlock, never bundled with another
instrument.

**Generic stat upgrades** — music-themed names, applied to **every**
instrument (current arsenal *and* instruments unlocked later, via
player-level multipliers `speedMul`/`areaMul`/`damageMul`/`quantityBonus`):

| Upgrade | Effect |
|---|---|
| **Tempo Up** | ×1.1 on every speed stat (`speed`, `bulletSpeed`, `throwSpeed`, `rotationSpeed`, `closingSpeed`, `cloudSpeed`) |
| **Volume Up** | ×1.1 on every **area** stat (`radius`, `size`, `width`, `height`, `length`, `wallLength`, `arcSize`, `maxDistance`, `markRadius`, `arcHeight`, `currentRange`) — no audio volume change |
| **Gain Up** | ×1.1 on every `damage` stat |
| **Chord Up** | +1 `count` on every attack |
| **BPM Up** | `music.tempoMultiplier` (capped at 2.0) — speeds the song and the beat-locked attacks |
| **Delay Up** | `music.setDelay(mix, feedback, beats)` — beat-timed echo |
| Size Up / Enemy Slowdown / XP Boost | player/enemy stats |

**Level gate** — instrument upgrades are hidden until the arsenal has
"earned" them: the Nth attack requires player level ≥ 3N (1st at level 3,
2nd at 6, …). Before that the pool rolls stat upgrades only. While the gate
is open, a random eligible instrument upgrade is **always** one of the menu
choices (injected if the roll missed one).

### 5. Your two verification tools

```bash
love . --midi                  # standalone harness: audition songs/layers
luajit tests/test_engine.lua   # 45 engine assertions, no LÖVE needed
```

The harness (`main_midi.lua`) has seek, per-track mute, tempo, delay and a
"g" key that previews the exact drums-only start the real game uses.

## Engine API cheat sheet

Everything lives in `MIDI.Player` unless noted. Call player methods with a
dot (`music.play()`), not a colon.

| You want | Call |
|---|---|
| Play / pause / stop | `music.play()` `music.pause()` `music.stop()` |
| Jump to position (seconds) | `music.seek(12.5)` |
| Per-frame update | `music.update(dt)` — once per frame, always |
| Seconds per beat (real time) | `music.getBeatDuration()` |
| Position inside the beat, 0..1 | `music.getBeatPhase()` |
| Completed beats since start | `music.beatCount` (monotonic, loop-safe) |
| Run code on every beat | `music.onBeat(function(n) ... end)` |
| One-shot drum hit | `music.sfx(nil, 36, 127, 0.3)` |
| One-shot melodic stab | `music.sfx(1, 60, 110, 0.5)` |
| Mute / unmute a track | `music.setTrackMuted(track, true)` |
| Song speed multiplier | `music.tempoMultiplier` (field, cap it in code) |
| Echo | `music.setDelay(mix, feedback, beats)` (0 mix = off) |
| Loop the song | `music.loop` (default true) |
| Song length / position | `music.loopLength` / `music.songPos` |
| Active voices | `music.synth.voiceCount` |
| Load sounds | `music.synth.loadInstrument(id, file)` / `music.synth.loadDrum(note, file)` |

## Recipes

**Add a new attack with its own instrument** — declare it like the others in
`source/attacks.lua`; firing, sound and bar come free:

```lua
beatDiv = 4,
sound = { inst = 1, note = 48, vel = 110, dur = 0.5 },  -- piano stab, once per bar
-- or drums: sound = { inst = nil, note = 38, vel = 120, drum = true },
```

**React to a specific beat anywhere in the game:**

```lua
if music and music.beatCount % 4 == 0 then ... end   -- once per bar
```

**Swap or add a song** — drop a `.mid` into `songs/` and change
`currentSongPath` in `source/screens/game.lua`. See the next section for the
full song format.

**Add an instrument sound** — add one line to `roster.INSTRUMENTS`
(`source/roster.lua`) with its sample file, and drop the file into `samples/`.
Everything else (loading, palettes, layer assignment) picks it up
automatically.

## Rock/metal song format & the roster

The progression is data-driven from two places: `source/roster.lua` (what can
unlock, in which order) and the song file itself (which layers exist).

**Roster entries have their own "Add X" upgrade**, freely choosable in any
order. Each unlock brings exactly one instrument: roster entry *k* pairs with
song layer *k−1* (entry 1 is the drum kit itself), so "Add Synth" also
unmutes the first melodic track with the synth sample.

Compose your song with tracks in this order (drums first, always channel 10):

| Song track | Layer | Instrument sample | Unlocks attack |
|---|---|---|---|
| 1 | — (drums) | kick / snare / hihat / crash + kit extras | Circle (Drums entry) |
| 2 | layer 1 | `samples/synth.mp3` | Fire Tower |
| 3 | layer 2 | `samples/rhythm_guitar.mp3` | Bouncing Knife |
| 4 | layer 3 | crash cymbals on their **own track** | Random Circle |
| 5 | layer 4 | `samples/lead_guitar.mp3` | Laser Beam |
| 6 | layer 5 | `samples/piano.mp3` | V-Wall |
| 7+ | layer 6+ | bass / organ / bells / timpani | Radial, Boomerang, Blood Arc, ... |

Rules of thumb:

- **Drums are one instrument**: the whole kit lives on one channel-10 track.
  Extra kit pieces (tom 41, gong 52, cowbell 56, china 57) just need their
  sample in `samples/` named after the registry entry.
- **Crash as a separate layer** requires crash hits on their own track (any
  channel) — inside the drum track they're part of the kit, not a layer.
- **Track names are hints**: a track named "Lead Guitar" always plays the
  lead guitar sample regardless of its position (`roster.
  instrumentIdForTrackName`). Unnamed tracks fall back to positional pairing.
- **Short songs are fine**: a song with fewer layers simply gives later
  unlocks no song layer (attack-only); the roster still completes.
- **Characters pick the starter**: each character in
  `source/screens/characters.lua` has `starter = <roster index>`; that
  instrument's attack and its song layer play from the first beat. The
  Drummer (1) starts with Circle/drums, the Soloist (5) starts with the
  Laser/lead guitar, etc.

**Per-song palettes** — the same attack can be a different instrument per
song. In `source/roster.lua`:

```lua
roster.PALETTES = {
  default = {},                       -- applies to every song
  ["songs/your_metal_song.mid"] = {
    [9] = "gong",                     -- Blood Arc plays the gong here
    [2] = { prefer = { "china", "crash" } },   -- first available wins
    [6] = { instrument = "leadGuitar", note = 79 },  -- exact control
  },
}
```

Resolution order per attack: this song's palette → `default` palette → the
roster entry's `prefer` list (first *loaded* instrument) → the entry's
built-in sound. A palette naming an instrument whose sample file is missing
still wins (the attack stays silent until you add the file); `prefer` lists
instead skip to the next available choice.

Sample files go into `samples/` as **WAV, OGG or MP3** — the loader tries all
three extensions automatically, so register them extensionless in
`roster.INSTRUMENTS` (`file = "samples/synth"`) and drop any format in.
Still missing from the current set: `tom` and `china` (Flame Thrower stays
silent until `samples/tom` exists).

## Conventions & gotchas

- Samples are resampled/downmixed to 44.1 kHz mono **at load** — any of
  WAV/OGG/MP3 at any sample rate works (48 kHz stereo MP3s are fine).
- Missing sample files are **silent skips** (melodic falls back to piano);
  only decode failures print a warning.
- Drum one-shots play at pitch 1.0; melodic `sfx` pitches by MIDI note
  (60 = C4).
- `loadDrum` uses the General MIDI note map (36 kick, 38 snare, 41 tom,
  42 closed hihat, 49 crash, 52 gong/chinese, 56 cowbell, 57 china).
- Always nil-check `music` in shared code (`attacks.lua` does: `music and ...`)
  so the game still runs if audio is missing.
- Voice caps are handled internally (32 voices, oldest stolen); master output
  is clamped, but huge stacks still get loud.

## Debugging

| Symptom | Likely cause |
|---|---|
| Silence, no warnings | All tracks muted (`1-9` in the harness), a locked layer, or an attack whose sample file is missing (drum one-shots are silent until the file exists) |
| Music stops during menus | `music.update(dt)` skipped that frame — keep it above any early return |
| No "Add Instrument" upgrade | All roster entries are already unlocked, or the level gate is still closed (next unlock needs level 3N) |
| Attack plays piano but should be guitar/synth | Melodic sample missing — the engine falls back to instrument 1 until you add the file |
| Wrong-pitched drums | Drum note not in the GM map you loaded, or sample is melodic material |
| Song doesn't loop | File ends in silence — loop point is last note + 1.5 s tail |

Verify the engine in isolation with `luajit tests/test_engine.lua` and audition
arrangements with `love . --midi` before touching game code.
