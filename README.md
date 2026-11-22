# Codename Engine for PS5 (unofficial port)

An unofficial port of [Codename Engine](https://github.com/CodenameCrew/CodenameEngine),
the Friday Night Funkin' engine, to jailbroken PlayStation 5 consoles, as a native
homebrew app (`PPSA52210`).

> **This port was made with AI help and is not made, checked or supported by the
> Codename Engine team, the Funkin' Crew or Sony.** Report its bugs here, not to
> Codename Engine. If you enjoy it, support the people who made the game and the engine
> by playing them on PC, where both are free:
> [codename-engine.com](https://codename-engine.com) ·
> [Friday Night Funkin' on itch.io](https://ninja-muffin24.itch.io/funkin).
> The game shows this notice when it starts.

**Status: beta.** The game code has been run in the Linux build of the port; the
console layer (SDL drivers, linking, packaging) is being tested on hardware now.
0.1.0 crashed at start-up on a PS5; 0.1.1 fixes that cause. Please report problems in
[Issues](https://github.com/Richie133/Friday-Night-Funkin-Codename-Ps5-port/issues)
with `/data/codename-ps5/logs/codename.log`, or a photo of the crash screen: each
release has `PPSA52210-symbols.txt.gz`, the function addresses of its `eboot.bin`
(the console loads it at `0x400000`; subtract that from the addresses it shows).

## What it adds to Codename Engine

- **Controller play.** Notes on the D-pad, either stick, or □ ✕ △ ○ (left, down,
  up, right). OPTIONS pauses. Every connected DualSense works.
- **Touchpad as a mouse.** Slide to move the pointer, click to click, two-finger
  click to right-click. Pointer speed is in the options.
- **Chart editor on the touchpad.** Click the touchpad during a song to open Codename's
  chart editor on that song (can be turned off).
- **USB keyboard and mouse**, as on PC (keyboard controls, editors, typing).
- **Mod browser** (△ on the main menu): GameBanana's
  [Codename mod category](https://gamebanana.com/mods/cats/34764), all of
  [FNF on GameBanana](https://gamebanana.com/games/8694) (with Psych Engine and
  V-Slice filters), search, and [Game Jolt's FNF games](https://gamejolt.com/games/best/tag-fnf).
  Each mod has a page with pictures, description and files; ✕ downloads and installs it.
  Downloads run in the background (OPTIONS shows them).
- **Custom on-screen keyboard** for searching mods: ✕ types, ○ deletes, △ space,
  □ shift, L1/R1 move the cursor, OPTIONS searches. The touchpad pointer and a USB
  keyboard work too.
- **Psych Engine mods**: converted when installed (charts, events, characters, stages,
  weeks, icons), and their Lua scripts run on Lua 5.1 through a Psych API layer
  (sprites, texts, tweens, timers, sounds, cameras, properties, input, saves,
  `runHaxeCode`...). Psych's built-in events (Hey!, Camera Follow Pos, Change Scroll
  Speed, Set Property...) are played too.
- **V-Slice (base game 0.5+) mods**: songs, charts, characters, stages and levels
  converted when installed.
- **Mod menu** (□ on the main menu): every installed mod with its page; ✕ plays it,
  △ opens the browser, □ deletes it.
- **Picture settings** (Options > PS5 > Picture): 1080p / 1440p / 4K, 60 or 120 Hz,
  V-Sync (off by default), frame rate up to 240, quality, antialiasing, shaders,
  low-memory mode.
- **Low input delay**: V-Sync off, uncapped update rate up to 240 FPS, controller
  read every frame.

What does not work: video cutscenes (no video decoder on the console), Discord, the
update checker, `.ndll` plugins, Psych `.hx` scripts and shaders in Psych Lua scripts.
Codename's own HScript mods work as on PC.

## Install

1. Download `PPSA52210.zip` from the
   [latest release](https://github.com/Richie133/Friday-Night-Funkin-Codename-Ps5-port/releases).
2. Install it with your homebrew store or app installer, as any `PPSAxxxxx.zip` app
   folder (it needs a jailbroken console that runs native homebrew apps).
3. Start "Codename Engine (PS5 port)".

Mods go to `/data/codename-ps5/mods/`: the browser puts them there, and you can copy
Codename mod folders there over FTP too. Saves, options and logs are in
`/data/codename-ps5/`.

## Controls

| | Controller | Keyboard |
|---|---|---|
| Notes | D-pad, sticks, □ ✕ △ ○ | as on PC (WASD / arrows) |
| Select / back | ✕ / ○ | Enter / Esc |
| Pause | OPTIONS | Enter |
| Mod menu / mod browser (main menu) | □ / △ | Tab / F |
| Chart editor (in a song) | touchpad click | 7, in developer mode (as on PC) |
| Pointer | touchpad | mouse |

The CREATE button belongs to the system on a PS5, so the port does not use it.

## Building

Linux (or WSL) with Haxe 4.3.7, Neko, clang 18 and lld 18. The GitHub workflow
(`.github/workflows/build.yml`) does all of it, and publishes the zip for `v*` tags.

```sh
tools/setup-haxelibs.sh        # the Haxe libraries, at the commits the port uses
ps5/tools/build-ps5.sh         # -> dist/PPSA52210/ and dist/PPSA52210.zip
```

A Linux build of the port, for testing on PC:

```sh
cd engine && ln -s ../.deps/codename/assets assets   # Codename's assets (see below)
haxelib run lime build linux -release
```

`engine/` is Codename Engine's source (commit in `engine/UPSTREAM_COMMIT`) with the
port's changes, which are all under `#if PS5_PORT` / `#if ps5` or in
`engine/source/funkin/ps5/`. Its `assets/` folder is Codename's, taken from the same
commit (`git clone https://github.com/CodenameCrew/CodenameEngine .deps/codename`).
How the console build works is in [`ps5/README.md`](ps5/README.md).

## Credits and licences

- [Codename Engine](https://github.com/CodenameCrew/CodenameEngine) by CodenameCrew
  (Apache-2.0, `engine/LICENSE-CodenameEngine.txt`), and Friday Night Funkin' by the
  Funkin' Crew. The Codename team asks that the engine not be re-released as a whole
  on other platforms; this port is a fan project, shared as source and a homebrew
  build, and will be taken down if they ask.
- HaxeFlixel, OpenFL, Lime, hxcpp and Codename's forks of them; Psych Engine
  (ShadowMario) and V-Slice (Funkin' Crew) for the formats the converters read.
- [ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk),
  [ps5-opengl](https://github.com/darkxex/ps5-opengl), the ps5-native-app-boilerplate
  and the PacBrew ports; Lua 5.1 (MIT).

The port's own code is GPL-3.0-or-later (`LICENSE`); see `THIRD_PARTY_NOTICES.md` for
every part and its licence.
