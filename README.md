# NoOneItsGOnnaHurtYou

A rhythm-orbit arena survival game (Vampire-Survivors-lite) built with **LÖVE2D**.

You orbit the center of the arena. Enemies converge from the edges — your only defense is
an auto-firing circular blast that pulses **in time with the music's BPM**. Level up, pick
roguelike upgrades, and speed the music up. One touch from the center and you're done —
*no one it's gonna hurt you*… except the one thing in the middle.

## The MIDI twist

The `midi` branch adds the game's signature feature: a **from-scratch Standard MIDI file
parser and sample-based synthesizer** (pure Lua — no libraries). The soundtrack is a real
`.mid` file played live, and the "BPM Up" upgrade raises the music's `tempoMultiplier` —
**the song speeds up as your attack rate increases**. Music and gameplay are locked
together: survive long enough and your own theme song becomes unbearable.

## Controls

| Key | Action |
|---|---|
| Left / Right (or A / D) | Orbit the center |
| Up / Down + Enter | Pick an upgrade on level-up |
| Esc | Back (menus) |

## Running

Install [LÖVE 2D](https://love2d.org/) (11.x), then:

```bash
love .
```

from this repository's root directory (or zip the folder and open it with LÖVE).

## Structure

```
main.lua            entry point / LÖVE callbacks
source/states.lua   screen state machine
source/screens/     mainmenu · characters · options · game · gameover
source/upgrades.lua level-up upgrade pool
source/attacks.lua  attack implementations
source/audio.lua    audio helpers
plugins/midi_engine.lua   MIDI parser + sample synth (the fun part)
songs/              soundtrack (.mid)
samples/            drum/instrument one-shots
```

## Status

Playable and fun. Rough edges: character select is a placeholder grid, game-over screen
is bare, and the protege selection does nothing yet.
