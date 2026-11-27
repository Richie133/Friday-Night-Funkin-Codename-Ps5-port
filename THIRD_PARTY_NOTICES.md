# Third-party notices

The Codename Engine PS5 port is licensed under GPL-3.0-or-later (`LICENSE`): the
console build statically links GPL-3.0-or-later code (ps5-opengl and the native-app
boilerplate), so the app as a whole is GPL-3.0-or-later. It includes or adapts the
following.

## The engine (`engine/`)

| Component | Where | Copyright | Licence |
|---|---|---|---|
| Codename Engine, commit in `engine/UPSTREAM_COMMIT`, with the port's changes (marked `PS5_PORT` / `ps5`) | `engine/` except the rows below | CodenameCrew and contributors | Apache-2.0 (`engine/LICENSE-CodenameEngine.txt`) |
| Codename Engine's assets (not stored here: fetched from the same commit at build time) | `engine/assets` | CodenameCrew; Friday Night Funkin' assets by the Funkin' Crew | as in the Codename Engine repository |
| The port's game code: mod browser and installer, mod menu, on-screen keyboard, options, warning | `engine/source/funkin/ps5/`, `engine/assets-overlay/` | Richie133 and contributors | GPL-3.0-or-later |
| Mozilla CA certificate store, as packaged by Debian's ca-certificates | `engine/assets-overlay/ps5/cacert.pem` | Mozilla and the CA program participants | MPL-2.0 |

## The console layer (`ps5/`, `tooling/`, `tools/`, `runtime/`)

| Component | Where | Copyright | Licence |
|---|---|---|---|
| SDL3 platform drivers (video over EGL, pad, touchpad, keyboard, mouse, audio, paths), adapting ps5-payload-dev/SDL (SDL2 port, John Törnblom, zlib) and ps5-opengl's SDL2 bridge (BlackBearReloaded, GPL-3.0-or-later) | `ps5/sdl/` | Richie133 | GPL-3.0-or-later |
| SDL3 build configuration for the private platform | `ps5/sdl/SDL_build_config_private.h`, `ps5/lime/` | Richie133 | zlib |
| Console glue: log, browser, notifications, DNS and socket shims (adapted from the boilerplate's libcurl support and KamTape PS5) | `ps5/native/codename_ps5.c` | Richie133; BlackBearReloaded | GPL-3.0-or-later |
| DNS query builder | `ps5/native/dns.*` | SponsorBlock for PS5 contributors | GPL-3.0-or-later |
| App heap for ps5-opengl | `ps5/native/app_heap.c` | (C) 2026 BlackBearReloaded | GPL-3.0-or-later |
| ps5-native-app-boilerplate: build scripts, `tooling/native` (ps5-native-tool, PIE linker script, CRT), clean-room `runtime/libc.prx` | `tooling/`, `tools/*.sh` (except `setup-haxelibs.sh`), `tools/zip-open-modes.py`, `runtime/` | (C) 2026 BlackBearReloaded | GPL-3.0-or-later |
| The touchpad data offset and `sceAudioOut` parameters | `ps5/sdl/SDL_ps5.c` | ZiZc3 and Ruffle Flash PS5 contributors | GPL-3.0 |
| hxcpp and Lime patches for the console | `ps5/hxcpp/`, `ps5/tools/patch-libs.py`, `ps5/lime/openal/` | Richie133 | GPL-3.0-or-later |

## Linked at build time (not stored here)

The build downloads these into `.deps/` and links them into `eboot.bin`, under their
own licences:

- Codename Engine's forks of [hxcpp](https://github.com/CodenameCrew/cne-hxcpp),
  [Lime](https://github.com/CodenameCrew/cne-lime) (MIT; with SDL3 (zlib), OpenAL Soft
  (LGPL-2.0-or-later), FreeType, HarfBuzz, libpng, libjpeg-turbo, libogg, libvorbis,
  Opus, zlib, mbedTLS, curl, cairo, pixman, dr_libs, Dear ImGui under theirs),
  [OpenFL](https://github.com/CodenameCrew/cne-openfl) and
  [HaxeFlixel](https://github.com/CodenameCrew/cne-flixel) (MIT), flixel-addons,
  flixel-animate, hscript-improved, hxWebSockets, foxlite, haxe-markdown, nape-haxe4,
  hxp, format and svg (see `tools/setup-haxelibs.sh` for the exact repositories).
- [ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk) (headers, import stubs,
  libc++, libunwind) and the [PacBrew](https://github.com/ps5-payload-dev/pacbrew-repo)
  ports of libarchive (BSD-2-Clause), xz/liblzma (0BSD/public domain), zstd (BSD),
  bzip2 (bzip2 licence) and zlib (zlib).
- [ps5-opengl](https://github.com/darkxex/ps5-opengl) (GPL-3.0-or-later; Mesa under
  MIT and its own notices).

## Online services

The mod browser reads GameBanana's and Game Jolt's public websites. Mods belong to
their authors; the port downloads them only when you ask.
