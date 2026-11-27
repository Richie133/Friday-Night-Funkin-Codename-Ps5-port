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
| `native/` | C linked next to the engine: the log file, crash reports (`crash_report.c`), the browser and notification calls the game makes (`funkin.ps5.PS5Native`), name lookup and socket shims for a sandboxed title, the heap ps5-opengl uses, and libc entry points the clean-room runtime lacks. |
| `tools/patch-libs.py` | The small edits hxcpp and Lime need; they only act on `-Dps5`, so the same checkouts still build for Linux. |
| `tools/build-ps5.sh` | The whole build. |

The game code needs few changes for the console (`engine/source/funkin/ps5/` and the
`#if ps5` lines): files live in `/app0/` (read-only) and `/data/codename-ps5/`; the app
folder cannot be listed, so the build writes `ps5-files.txt` and `funkin.ps5.AppFiles`
answers listings from it; HTTPS uses the certificates in `assets/ps5/cacert.pem`.

## Things to know

- The CREATE button is the system's: the port uses □ and △ instead.
- `/data/codename-ps5/logs/codename.log` has the game's output; send it with bug reports.
- When Codename's own error screen comes up, the error also goes to a notification and
  to `/data/codename-ps5/logs/error.txt` (`PS5.reportError`).
- When the game stops on a failed assertion, a crash signal or `std::terminate`, it shows
  a notification with the reason and writes the details and the call stack to
  `/data/codename-ps5/logs/crash.txt`. Addresses there are `eboot+0x…` offsets into
  `eboot.bin`, the numbering of each release's `PPSA52210-symbols.txt.gz`; the console's
  own error screen shows them plus `0x400000`.
- The working folder cannot be changed on the console (`Sys.setCwd` fails without an
  error), so Codename's relative paths are absolute there: `PS5.DATA_DIR` for mods,
  addons and autoload, `PS5.TEMP_DIR` for `.temp`. New relative paths in engine code
  need the same.
- Dear ImGui (Codename's debug console): multi-viewport stays off (one window), and its
  checks (`IM_ASSERT`) are logged instead of ending the game (`patch-libs.py`,
  `CNE_PS5_IMGUI_SOFT_ASSERT` in `hxcpp/ps5-toolchain.xml`, `native/crash_report.c`).
- Libraries that `dlopen()` a system library (as Dear ImGui's GL loader did with libGL)
  find nothing on the console: give them the function directly (`patch-libs.py`).
- `display.cfg` is written by Options > PS5 > Picture and read before the window opens,
  so resolution and refresh rate apply at the next start.
- Being tested on a console now (0.1.0 and 0.1.1 stopped at start-up; see the release
  notes). The likeliest trouble spots are the SDL drivers (`sdl/SDL_ps5.c`), the
  keyboard and mouse libraries (loaded at run time, only when the system has them),
  and memory use with large mods.
- Only some system libraries are loaded for a native title; a function imported from
  another one is left as a null pointer (the 0.1.0 crash). `sceKernelLoadStartModule`
  them at run time instead (`cne_ps5_load_module` in `native/codename_ps5.c`).
