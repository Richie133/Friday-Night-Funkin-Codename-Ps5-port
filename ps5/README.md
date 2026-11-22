# How the PS5 build works

Codename Engine is HaxeFlixel on OpenFL on Lime, compiled to C++ by hxcpp. On a PC,
Lime runs on SDL. The PS5 build keeps all of that and gives SDL a console back end,
then links everything into one native homebrew app.

```
engine (Haxe) --hxcpp, PS5 toolchain--> libApplicationMain.a ─┐
Lime native + SDL3 + ps5/sdl drivers --hxcpp-----> liblime.a ─┤
ps5/native (log, DNS, shims, heap), tooling/native (CRT) ─────┤ prospero-lld
ps5-opengl (EGL + OpenGL on Mesa), libc++, libunwind ─────────┤ ──> PIE
PacBrew: libarchive, liblzma, libzstd, libbz2, zlib ──────────┘
            ps5-native-tool: PS5 ELF + fake-signed SELF ──> dist/PPSA52210/eboot.bin
```

`ps5/tools/build-ps5.sh` runs all of it; the steps are listed at its top.

## Pieces

| Folder | What it is |
|---|---|
| `hxcpp/ps5-toolchain.xml` | hxcpp's compiler settings for the console: clang 18 with `-target x86_64-sie-ps5` against the payload SDK, static libraries only. `-Dps5` picks it (`patch-libs.py` adds that to hxcpp's build tool). |
| `lime/sdl-files-ps5.xml` | The SDL3 sources Lime builds for the console, plus `sdl/SDL_ps5.c`; it replaces Lime's own list on `-Dps5`. |
| `lime/openal/` | OpenAL Soft settings for the console (audio goes out through SDL3). |
| `sdl/` | SDL3's private-platform slots, filled for the PS5: the window and OpenGL context (EGL from ps5-opengl, mode from `/data/codename-ps5/display.cfg`), DualSense pads with the touchpad, the touchpad as a pointer, USB keyboards and mice, `sceAudioOut`, and the app's paths. |
| `native/` | C linked next to the engine: the log file, the browser and notification calls the game makes (`funkin.ps5.PS5Native`), name lookup and socket shims for a sandboxed title, the heap ps5-opengl uses, and libc entry points the clean-room runtime lacks. |
| `tools/patch-libs.py` | The small edits hxcpp and Lime need; they only act on `-Dps5`, so the same checkouts still build for Linux. |
| `tools/build-ps5.sh` | The whole build. |

The game code needs few changes for the console (`engine/source/funkin/ps5/` and the
`#if ps5` lines): files live in `/app0/` (read-only) and `/data/codename-ps5/`; the app
folder cannot be listed, so the build writes `ps5-files.txt` and `funkin.ps5.AppFiles`
answers listings from it; HTTPS uses the certificates in `assets/ps5/cacert.pem`.

## Things to know

- The CREATE button is the system's: the port uses □ and △ instead.
- `/data/codename-ps5/logs/codename.log` has the game's output; send it with bug reports.
- `display.cfg` is written by Options > PS5 > Picture and read before the window opens,
  so resolution and refresh rate apply at the next start.
- Not tested on a console yet. The likeliest trouble spots are the SDL drivers
  (`sdl/SDL_ps5.c`), the mouse library (loaded only when the system has it), and
  memory use with large mods.
