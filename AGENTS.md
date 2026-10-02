# AGENTS.md — auto-survivors

A Vampire Survivors-style run in **Zig 0.14.1 + raylib**: a party in a 3x3 formation, twenty minutes, lesser liches along the way and the lich at 20:00.
Build setup, sprite lighting and font come from `..\zig-roguelike-scratch`.

Prefer no comments in code. Don't make product/design decisions — ask. Don't commit, push or branch unless asked.

## Build & verify

- `zig` is NOT on PATH; `_zig.cmd` names it. `check.cmd` (type-check) · `build.cmd` · `run.cmd` (ReleaseFast) ·
  `test.cmd [filter]` · `shot.cmd` (headless frames into `shots\`: run, level, place, recruit, pause, options, title).
- **EVERY MODULE MUST BE NAMED IN `main.zig`'s `test {}` BLOCK** — `build.zig` panics otherwise.
- Verify with tests that print the number. Do NOT launch the interactive window. No autoplay bot judges balance: the
  owner plays it.
- `docs\roster.html` is the class/upgrade/foe reference, published at https://claude.ai/artifact/WW4yedgJ97HMhCsKbeXe8s.
  After changing a class, upgrade or foe: build zig-out-dev, `python tools\roster.py`, republish the same file.
- Sprites are placeholders drawn by `tools\paint.py`, card icons (`icon_<upgrade|branch|move|rest>.png`) by
  `tools\icons.py`; every `sfx_*.wav` and `music.ogg` is synthesized by
  `tools\sound.py` (numpy, scipy, ffmpeg). Every PNG, TTF, WAV and OGG in `assets\` is embedded.

## Laws

- **THE SLOTS STAY PUT; THE FACING TURNS** (`play/formation.zig`). Heroes hold world-aligned slots of the 3x3; the
  facing is the 8-way direction of movement, and it alone decides the front row and the rear.
- **`play/run.zig` IS THE WHOLE SIMULATION**, stepped at `run.STEP`; it reads no device and no screen. The view
  drains its `events` for effects.
- **`hero.Hero` IS A HERO'S PROGRESSION; `run.Member` IS IT IN THE FIELD.** Card text and the stat it changes come
  from the same constants in `hero.zig`.
- **WHAT A HERO LEAVES IN THE FIELD LIVES IN `Run`'s POOLS**: a druid's `vines` (each holds its tile), a bard's
  `clouds` (foes in one are `charm`ed onto the party's side, half as long for a boss), a necromancer's
  `skeletons` (foes hunt them like heroes, `markOf`). Lobbed foe `shells` arc over the Shield Wall; a warned one
  marks the ground it lands on.
- **`formation.beside` IS UP, DOWN, LEFT, RIGHT, NEVER DIAGONAL**: the bard's harp (`Run.power`) and the
  necromancer's chill (`Run.healOf`) reach only those slots.
- **`core/input.zig` IS THE ONLY FILE THAT TOUCHES A DEVICE.** The pad is primary; the keyboard mirrors it.
- **`gfx/light.zig` IS EVERY LIGHT.** The ground draws at full brightness and one 2x-modulate pass of the light map
  lights it; bodies are lit by their own shader from silhouette-bevelled normals. Index 0 of the lamps is the
  party's, which lights its heroes flat.
- **`sound/audio.zig` IS THE ONLY FILE THAT TOUCHES THE SPEAKERS.** Simulation events map to cues
  (`audio.cueOf`); each cue has a minimum gap so a horde stays a patter. `--shot` opens no audio device.
- **`gfx/fx.zig` IS EVERY EVENT'S AFTERMATH**: gore, stains and smoke before the light map, sparks, embers and
  bursts after it, and the view's shake. Poses (lunges, bites, recoil, squash) are `game.heroPose` / `foePose`,
  read from the simulation's timers; nothing in the simulation reads them.
- **`gfx/numbers.zig` IS EVERY FLOATING NUMBER**, from the amount on each hit, hurt, burn, poison and heal event:
  white hits (opacity by amount), gold crits (whole), red damage to the party, orange burning, yellow-green poison,
  pale green healing.
- **EVERY ABILITY IS SEEN**: an effect without its own body draws a tell (`game.drawWards`: Shield Wall's arc, each
  archer's field; `fx`: Sanctuary's reach, Smite's wave, Lifeline's beam, Second Wind's motes).
- **EVERY DRAWN STRING IS ASCII.**
