# HANTU: The 25 Books

A first-person mobile horror game built in **Godot 4**. You are trapped in a dark
mansion with Hantu. Find **25 books** hidden across the rooms and corridors, then
escape through the sealed exit at the south end of the main hall.

Built for the **Mobile** renderer and landscape screens (1280x720 logical
resolution, `canvas_items` / `expand` stretch). It also runs on desktop with
mouse and keyboard.

---

## Requirements

- **Godot 4.7** (tested with 4.7.2 stable). The project uses the Mobile renderer.
- **Python 3** only if you want to regenerate the level or audio (standard
  library only, no packages needed).

## Run

**Editor:** open `project.godot` in Godot 4.7 and press **F5**.

**Command line:**

```powershell
Godot_v4.7.2-stable_win64.exe --path "C:\Coder\oneeye"
```

If the `.godot` folder is missing, let Godot import once first:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path "C:\Coder\oneeye" --import
```

## How to play

- Explore the mansion and pick up **25 books**. Three are hidden in each of the
  eight rooms and one sits in the main corridor.
- The **exit door** at the south end of the central corridor stays sealed until
  every book is collected. Walk up to it and press **TAKE / TRY** (or `E`) to
  check the seal.
- Once the 25th book is taken the door unlocks, the sign turns red-hot, and the
  way out opens. Reach the doorway to win.
- **Hantu** patrols the house. It only spots you if you are inside its vision
  cone and it has line of sight:
  - 18 m patrol sight range, 110 degree field of view, plus close-range
    awareness under ~3.2 m.
  - Once it sees you it chases out to 26 m, moving faster than your walk.
  - It catches you within about 1.5 m, then the jumpscare plays.
  - Breaking line of sight makes it search your last known position.
  - When the exit unlocks it becomes **enraged**: faster and redder.
- **Stamina**: holding sprint drains stamina. Emptying the bar locks sprinting
  until it recovers to 30%, so use it in bursts and listen for footsteps.

## Controls

### Desktop

| Input | Action |
| --- | --- |
| `W A S D` | Move |
| Mouse | Look |
| `Shift` (hold) | Sprint |
| `E` | Take book / try exit |
| `Esc` | Pause |

### Mobile / touch

- **Left thumbstick** — move.
- **Swipe the right side of the screen** — look around. Aim quickly to turn.
- **Hold RUN** — sprint while stamina lasts.
- **TAKE / TRY** — pick up a book or check the sealed exit.
- **II** (top right) — pause.

Touch UI, vibration feedback on detection and capture, and the on-screen hints
switch automatically based on whether a touchscreen is available.

## Audio

All 13 sounds are generated procedurally at build time and committed under
`assets/audio/`:

`ambience`, `heartbeat`, `chase`, `whisper`, `book`, `step`, `locked`,
`unlock`, `stinger`, `scream`, `jumpscare`, `win`, `ui_click`.

Ambience, heartbeat, chase and whisper are looping players; the rest play from a
one-shot pool. Audio ducks and mutes correctly on pause, win and capture.

## Project layout

```
project.godot             main scene, Sfx autoload, mobile renderer/orientation
scenes/
  main.tscn               entry scene (level is built at runtime)
  player.tscn             first-person controller, torch + fill light
  ghost.tscn              Hantu dance-card quad, gaze spotlight, glow
  book.tscn               collectible with glow and proximity light
scripts/
  game.gd                 level builder, state machine, interactions, win/caught
  player.gd               movement, stamina, touch/mouse look, head bob, footsteps
  ghost.gd                patrol / search / chase AI, vision + LOS, enrage
  book.gd                 pickup, bob, pulse, proximity light
  hud.gd                  menus, touch controls, jumpscare, end screens
  virtual_joystick.gd     custom left-thumb virtual stick
  audio_manager.gd        Sfx autoload: loops, one-shots, tension, win fade
assets/
  shaders/                world-space wall, floor, ghost, glow, overlay shaders
  audio/                  generated horror WAVs
data/map.txt              ASCII floorplan (35 x 27 cells, 3 m per cell)
HANTU.jpeg                monster texture
tools/
  make_map.py             regenerates data/map.txt
  generate_audio.py       regenerates assets/audio/*.wav
tests/
  smoke_test.tscn/.gd     headless gameplay + audio validation
```

### About the monster texture

The brief asked for `HANTU.png`, but the workspace only contained
`HANTU.jpeg`, so the JPEG is used directly. The ghost shader keys out the dark
background, brightens the portrait and adds a scanline/rim effect so it reads as
a floating apparition in the dark.

## Regenerating content

From the project root:

```powershell
python tools/make_map.py        # rebuilds data/map.txt (rooms, 25 books, exit)
python tools/generate_audio.py  # rewrites assets/audio/*.wav
```

`make_map.py` prints the floorplan and reachable cell count. It always produces
exactly 25 book spots, one spawn, one exit, and a doorway through the south
wall so the exit opens onto the moonlight.

After regenerating, reopen the project (or run `--import`) so Godot reimports
the changed assets. Remove stale `.import` files only if Godot complains.

## Tests

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path "C:\Coder\oneeye" res://tests/smoke_test.tscn
```

The smoke test validates the map, 25 spawned books, reachability of every book,
the exit and the ghost spawn, loop setup for the ambience/heartbeat/chase/whisper
players, game start, ghost vision, wall occlusion, collecting all books, exit
unlocking and winning at the exit.

## Android export notes

1. Install the Godot export templates for 4.7 (Editor > Manage Export Templates).
2. Install a JDK and the Android SDK, then set the Android SDK path in
   Editor Settings > Export > Android.
3. Project > Export > Add > Android. The project is already configured for
   landscape (`window/handheld/orientation=4`), the Mobile renderer, and
   `canvas_items` stretch, so the touch HUD fills the screen.
4. Use **Export Project** (or **One-click Deploy**) to produce an APK/AAB.
   Touch controls appear automatically; desktop builds keep WASD/mouse.

## Credits

- Engine: Godot 4.7.2 stable (Mobile renderer, Jolt Physics).
- Monster texture: `HANTU.jpeg` (provided asset).
- All audio synthesized by `tools/generate_audio.py`.
- All environment art is procedural: geometry and shaders generated at runtime.
