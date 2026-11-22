#!/usr/bin/env bash
# Fetches the Haxe libraries the port builds with, at the commits it was made
# against, into .deps/haxelib/ (or $HAXELIB_DEPS), and points haxelib at them.
#
#   tools/setup-haxelibs.sh            fetch what is missing
#   tools/setup-haxelibs.sh --update   also move existing checkouts to the pins
#
# Needs git, haxe and neko on PATH. Builds hxcpp's build tool, and patches hxcpp
# and lime for the console (ps5/tools/patch-libs.py; the patches only act on -Dps5).
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
deps=${HAXELIB_DEPS:-$root/.deps/haxelib}
update=false
[[ ${1:-} == --update ]] && update=true

# name  url  commit  [subfolder haxelib should use]
libs=(
  "hxcpp https://github.com/CodenameCrew/cne-hxcpp 68faa524aa7a10af4fd6e835bb58d1ec4582ca1f"
  "lime https://github.com/CodenameCrew/cne-lime 60c8346626436907cb77fdc4ddb6f69c1322f93f"
  "openfl https://github.com/CodenameCrew/cne-openfl 74f5f97242fa31150d525559e514743398abd8f1"
  "flixel https://github.com/CodenameCrew/cne-flixel e05b0d0a3441be9bc6e42ec9e9cca9181eb7c65f"
  "flixel-addons https://github.com/CodenameCrew/cne-flixel-addons 3b35866c391ae44e8c9a7e3684c43821d4a86d29"
  "flixel-animate https://github.com/CodenameCrew/cne-flixel-animate 49cd4753f3227ab89e148f3c73d91fa18133b12a"
  "hscript-improved https://github.com/CodenameCrew/hscript-improved ae4a54d646df8cd35b38f97087e1bfaa9006933e"
  "hxWebSockets https://github.com/ianharrigan/hxWebSockets 264e1a630b15c8f28f3407dbded16c8dc20db796"
  "foxlite https://github.com/dwdvIl/foxlite 46183555a9a1fb515b20d1ffe344e2404b79650d"
  "markdown https://github.com/dpeek/haxe-markdown d4f20e8680441b1e3214b0e531307b3094283ed0"
  "nape-haxe4 https://github.com/HaxeFlixel/nape-haxe4 02ac91939af02457c0e8896472a04d04e94216c1 haxelib"
  "hxp https://github.com/openfl/hxp a060a749bfae3af190c50884cd89f89e5835abd6"
  "format https://github.com/HaxeFoundation/format 8922e1bc6630498ef3c64d90e0b58e733ea7219e"
  "svg https://github.com/openfl/svg e51f25adb17571031887d14c43edb1bd49e68172"
)

for tool in git haxe haxelib neko python3; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 2; }
done
mkdir -p "$deps"
[[ -d $(haxelib config 2>/dev/null || echo /nonexistent) ]] || haxelib setup "$deps/.repo" >/dev/null

for entry in "${libs[@]}"; do
  read -r name url commit sub <<< "$entry"
  dir="$deps/$name"
  if [[ ! -d $dir/.git ]]; then
    echo "==> $name"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q FETCH_HEAD
  elif $update && [[ $(git -C "$dir" rev-parse HEAD) != "$commit" ]]; then
    echo "==> $name -> ${commit:0:10}"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q -f FETCH_HEAD
  fi
  haxelib dev "$name" "$dir${sub:+/$sub}" >/dev/null
done

# lime's native libraries (SDL, OpenAL Soft, ...) are git submodules
if [[ ! -f $deps/lime/project/lib/sdl/CMakeLists.txt ]]; then
  echo "==> lime submodules"
  git -C "$deps/lime" submodule update --init --depth 1 --jobs 4
fi

python3 "$root/ps5/tools/patch-libs.py" "$deps/lime" "$deps/hxcpp" "$root"

# hxcpp's build tool (it is patched above, so it is built here)
if [[ ! -f $deps/hxcpp/hxcpp.n || $deps/hxcpp/tools/hxcpp/BuildTool.hx -nt $deps/hxcpp/hxcpp.n ]]; then
  echo "==> hxcpp build tool"
  (cd "$deps/hxcpp/tools/hxcpp" && haxe compile.hxml)
fi
echo "Haxe libraries ready in $deps"
