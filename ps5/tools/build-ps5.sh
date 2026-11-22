#!/usr/bin/env bash
# Builds the PS5 app: dist/PPSA52210/ (the app folder) and dist/PPSA52210.zip.
#
#   ps5/tools/build-ps5.sh [--skip-lime] [--skip-haxe]
#
# Steps (each one is skipped when its output is up to date, except where noted):
#   1. dependencies: payload SDK, ps5-opengl SDK, PacBrew (libarchive), the
#      host tools of the native app boilerplate, and the Haxe libraries
#   2. Lime's native side as a static library for the console (liblime.a)
#   3. the game's assets for the app folder (lime update linux)
#   4. the game: Haxe -> C++ -> libApplicationMain.a, with the PS5 toolchain
#   5. the port's C runtime (ps5/native) and the app entry (tooling/native)
#   6. link (prospero-lld), convert and sign (ps5-native-tool) -> eboot.bin
#   7. the app folder and its zip (every entry stored as 0777)
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
skip_lime=false
skip_haxe=false
for arg in "$@"; do
  case $arg in
    --skip-lime) skip_lime=true ;;
    --skip-haxe) skip_haxe=true ;;
    *) echo "usage: ps5/tools/build-ps5.sh [--skip-lime] [--skip-haxe]" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------- 1. dependencies
step "Dependencies"
bash "$root/tools/setup-native-dependencies.sh" >/dev/null
bash "$root/tools/prepare-opengl.sh"
export PS5_PAYLOAD_SDK=${PS5_PAYLOAD_SDK:-$root/.deps/native/ps5-payload-sdk}
export PS5_OPENGL_PREFIX=${PS5_OPENGL_PREFIX:-$(realpath "$root/.deps/ps5-opengl/current")}
export PS5_CLANG=${PS5_CLANG:-$(command -v clang-18)}
export LIME_PS5_DIR=$root/ps5
pacbrew=$(bash "$root/tools/setup-pacbrew-dependencies.sh" --resolve libarchive)
pacbrew_root=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["root"])' "$pacbrew")
homebrew=$pacbrew_root/user/homebrew
[[ -f $homebrew/lib/libarchive.a ]] || { echo "PacBrew has no libarchive.a in $homebrew/lib" >&2; exit 2; }
# libarchive's two headers on their own, so nothing else from PacBrew shadows the SDK's
mkdir -p "$root/build/ps5/include"
cp "$homebrew/include/archive.h" "$homebrew/include/archive_entry.h" "$root/build/ps5/include/"
export PS5_ARCHIVE_INCLUDE=$root/build/ps5/include
bash "$root/tools/build-host-tools.sh"
tool=$root/build/host/ps5-native-tool
if [[ -z ${HAXELIB_SKIP_SETUP:-} ]]; then
  bash "$root/tools/setup-haxelibs.sh"
fi
lime_dir=$(haxelib libpath lime)
lime_dir=${lime_dir%/}
hxcpp_dir=$(haxelib libpath hxcpp)
hxcpp_dir=${hxcpp_dir%/}
python3 "$root/ps5/tools/patch-libs.py" "$lime_dir" "$hxcpp_dir" "$root" >/dev/null
export HXCPP_COMPILE_THREADS=${HXCPP_COMPILE_THREADS:-$(nproc)}

# ---------------------------------------------------------------- 2. Lime
liblime=$lime_dir/ndll/PS5/liblime.a
if ! $skip_lime; then
  step "Lime for the PS5 (liblime.a)"
  (cd "$lime_dir/project" && haxelib run hxcpp Build.xml -Dps5 -Dstatic_link -DHXCPP_M64 \
    -DPS5_PAYLOAD_SDK="$PS5_PAYLOAD_SDK" -DPS5_OPENGL_PREFIX="$PS5_OPENGL_PREFIX" -DLIME_PS5_DIR="$LIME_PS5_DIR")
fi
[[ -f $liblime ]] || { echo "missing $liblime" >&2; exit 2; }

# ---------------------------------------------------------------- 3. assets
engine=$root/engine
[[ -e $engine/assets ]] || ln -s ../.deps/codename/assets "$engine/assets"
step "Game assets (lime update linux)"
(cd "$engine" && haxelib run lime update linux -release)
linux_bin=$engine/export/release/linux/bin

# ---------------------------------------------------------------- 4. the game
out=$engine/export/release/ps5
hxml=$out/build.hxml
mkdir -p "$out"
if ! $skip_haxe; then
  step "Codename Engine for the PS5 (Haxe -> C++ -> libApplicationMain.a)"
  (cd "$engine" && haxelib run lime display linux -release) > "$out/display.hxml"
  # the Linux build's settings, turned into the console's:
  python3 - "$out/display.hxml" "$hxml" "$PS5_ARCHIVE_INCLUDE" <<'PY'
import sys
drop = {"-D no-compilation", "-D linux", "-D DARK_MODE_WINDOW", "-D NDLLS_SUPPORTED", "--no-output"}
lines = []
for line in open(sys.argv[1]).read().splitlines():
    line = line.strip()
    if not line or line in drop:
        continue
    if line.startswith("-cpp "):
        line = "-cpp export/release/ps5/obj/"
    lines.append(line)
lines += ["-D ps5", "-D static_link", "-D toolchain=ps5", "-D HXCPP_M64", "-D NO_PRECOMPILED_HEADERS",
          "-D PS5_ARCHIVE_INCLUDE=" + sys.argv[3]]
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
PY
  (cd "$engine" && haxe "$hxml")
fi
libgame=$(find "$out/obj" -maxdepth 1 -name 'lib*.a' -newer "$hxml" -print -quit 2>/dev/null || true)
[[ -n $libgame ]] || libgame=$(find "$out/obj" -maxdepth 1 -name 'lib*.a' -print -quit)
[[ -n $libgame && -f $libgame ]] || { echo "the Haxe build left no static library in $out/obj" >&2; exit 2; }
echo "game: $libgame"

# ---------------------------------------------------------------- 5. native runtime
step "Native runtime"
build=$root/build/ps5
mkdir -p "$build/obj"
cc=(sh "$root/tooling/prospero-clang18")
objects=()
for source in "$root"/ps5/native/*.c; do
  object=$build/obj/$(basename "$source").o
  if [[ ! -f $object || $source -nt $object ]]; then
    echo "  CC $(basename "$source")"
    env PS5_PAYLOAD_SDK="$PS5_PAYLOAD_SDK" PS5_CLANG="$PS5_CLANG" USE_CCACHE=0 "${cc[@]}" \
      -std=gnu11 -O2 -ffunction-sections -fdata-sections -I"$PS5_OPENGL_PREFIX/include" -c "$source" -o "$object"
  fi
  objects+=("$object")
done
for name in app_crt app_cpp_runtime; do
  object=$build/obj/$name.o
  source=$root/tooling/native/$name.cpp
  if [[ ! -f $object || $source -nt $object ]]; then
    echo "  CXX $name.cpp"
    env PS5_PAYLOAD_SDK="$PS5_PAYLOAD_SDK" PS5_CLANG="$PS5_CLANG" USE_CCACHE=0 "${cc[@]}" \
      -std=c++20 -O2 -fno-exceptions -fno-rtti -ffunction-sections -fdata-sections -c "$source" -o "$object"
  fi
done

# ---------------------------------------------------------------- 6. link
step "Link"
group=$root/.deps/ps5-opengl/libps5opengl-group.a
wraps=()
for symbol in malloc calloc realloc free posix_memalign malloc_usable_size fcntl; do
  wraps+=("--wrap=$symbol")
done
stubs=("$PS5_OPENGL_PREFIX/lib/libSceAgc.so" "$PS5_OPENGL_PREFIX/lib/libSceAgcDriver.so")
"$PS5_PAYLOAD_SDK/bin/prospero-lld" \
  -T "$root/tooling/native/ps5-pie.ld" --eh-frame-hdr "${wraps[@]}" \
  --version-script "$root/tooling/native/app-symbols.map" \
  -e _start -o "$build/llvm-pie.elf" \
  "$build/obj/app_crt.o" "$build/obj/app_cpp_runtime.o" "${objects[@]}" \
  --start-group "$libgame" "$liblime" \
    "$homebrew/lib/libarchive.a" "$homebrew/lib/liblzma.a" "$homebrew/lib/libzstd.a" \
    "$homebrew/lib/libbz2.a" "$homebrew/lib/libz.a" "$group" \
  --end-group \
  --as-needed "${stubs[@]}" "$PS5_PAYLOAD_SDK"/target/lib/*.so
stub_options=()
for stub in "${stubs[@]}"; do stub_options+=(--stub "$stub"); done
"$tool" link --in "$build/llvm-pie.elf" --out "$build/eboot.elf" "${stub_options[@]}" \
  --stub-dir "$PS5_PAYLOAD_SDK/target/lib" --module-sdk 0x02000009 --companion-sdk 0x08050001 \
  --file-name eboot.elf

# ---------------------------------------------------------------- 7. app folder
step "App folder"
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$root/sce_sys/param.json")
bash "$root/tools/validate-assets.sh" "$root/sce_sys"
dist=$root/dist
app=$dist/$title_id
rm -rf -- "$app"
mkdir -p "$app/sce_sys" "$app/sce_module"
"$tool" self --sign --in "$build/eboot.elf" --out "$app/eboot.bin" --magic 0x1D3D154F
cp "$root/sce_sys/param.json" "$app/sce_sys/param.json"
for asset in icon0.png pic0.dds pic1.dds snd0.at9; do
  [[ -f $root/sce_sys/$asset ]] && cp "$root/sce_sys/$asset" "$app/sce_sys/$asset"
done
[[ -f $root/runtime/libc.prx ]] || bash "$root/tools/rebuild-libc.sh"
(cd "$root/runtime" && sha256sum --check --strict libc.prx.sha256)
cp "$root/runtime/libc.prx" "$app/sce_module/libc.prx"
"$tool" self --inspect --file "$app/sce_module/libc.prx" >/dev/null
# the game's files, as the Linux build lays them out next to its executable
cp -a "$linux_bin/assets" "$app/assets"
[[ -d $linux_bin/manifest ]] && cp -a "$linux_bin/manifest" "$app/manifest"
# /app0 cannot be listed on the console: the game reads its file list from here
(cd "$app" && find . -type f ! -path './sce_sys/*' ! -path './sce_module/*' ! -name eboot.bin -printf '%P\n' | LC_ALL=C sort > ps5-files.txt)
"$tool" self --inspect --file "$app/eboot.bin"

(cd "$dist" && rm -f "$title_id.zip" && python3 -m zipfile -c "$title_id.zip" "$title_id")
python3 "$root/tools/zip-open-modes.py" "$dist/$title_id.zip"
printf '\nBuild complete.\nApp folder: %s\nZip: %s\n' "$app" "$dist/$title_id.zip"
