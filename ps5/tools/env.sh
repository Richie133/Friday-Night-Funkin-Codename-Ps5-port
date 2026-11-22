# Environment for the PS5 build. Sourced by ps5/tools/*.sh; override any of these
# before sourcing to use your own copies.
#
#   PS5_PAYLOAD_SDK     ps5-payload-sdk (clang target files, libc, import stubs)
#   PS5_OPENGL_PREFIX   ps5-opengl SDK's sdk/ folder (EGL, GL headers, static Mesa)
#   PS5_CLANG           clang 18
#   LIME_PS5_DIR        this repository's ps5/ folder (SDL drivers, Lime file list)

ps5_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export PS5_REPO=$ps5_repo
export PS5_DEPS=${PS5_DEPS:-$ps5_repo/.deps}
export PS5_PAYLOAD_SDK=${PS5_PAYLOAD_SDK:-$PS5_DEPS/ps5-payload-sdk}
export PS5_OPENGL_PREFIX=${PS5_OPENGL_PREFIX:-$PS5_DEPS/ps5-opengl-sdk/sdk}
export PS5_CLANG=${PS5_CLANG:-clang-18}
export LIME_PS5_DIR=${LIME_PS5_DIR:-$ps5_repo/ps5}
export HAXELIB_PATH=${HAXELIB_PATH:-$ps5_repo/.deps/haxelib}
