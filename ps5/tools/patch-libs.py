#!/usr/bin/env python3
"""Applies the PS5 port's changes to Codename's library forks (cne-lime, cne-hxcpp).

Usage: patch-libs.py <lime folder> <hxcpp folder> <repo root>

Every change is a plain find-and-replace that is checked, and is skipped when it is
already there, so the script can run again on the same checkouts. The changes:

  hxcpp  toolchain/ps5-toolchain.xml      the PS5 compiler (ps5/hxcpp/ps5-toolchain.xml)
         tools/hxcpp/BuildTool.hx          -Dps5 picks that toolchain
         src/hx/libs/std/{Process,Sys}.cpp <sys/wait.h> on the console
  lime   project/Build.xml                 OpenAL Soft and desktop GL on -Dps5, and the
                                           PS5 SDL file list (ps5/lime/sdl-files-ps5.xml)
         lib/custom/openal/include         OpenAL Soft settings for the console
                                           (ps5/lime/openal)
"""
import os
import shutil
import sys


def edit(path, old, new, marker=None):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if (marker or new) in text:
        return False
    if old not in text:
        sys.exit(f"patch-libs: cannot find the text to change in {path}:\n{old}")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(old, new, 1))
    return True


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    lime, hxcpp, repo = (os.path.abspath(p) for p in sys.argv[1:])
    ps5 = os.path.join(repo, "ps5")
    changed = []

    # hxcpp: the toolchain file, and -Dps5 selecting it
    shutil.copyfile(os.path.join(ps5, "hxcpp", "ps5-toolchain.xml"), os.path.join(hxcpp, "toolchain", "ps5-toolchain.xml"))
    build_tool = os.path.join(hxcpp, "tools", "hxcpp", "BuildTool.hx")
    if edit(build_tool,
            '      else if (defines.exists ("gcw0"))',
            '      else if (defines.exists ("ps5"))\n      {\n         defines.set ("toolchain", "ps5");\n         defines.set ("BINDIR", "PS5");\n      }\n      else if (defines.exists ("gcw0"))',
            marker='defines.set ("toolchain", "ps5");'):
        changed.append("hxcpp BuildTool")

    # hxcpp's runtime: the console's libc keeps the wait() macros in <sys/wait.h>
    std = os.path.join(hxcpp, "src", "hx", "libs", "std")
    if edit(os.path.join(std, "Process.cpp"),
            "#   if defined(ANDROID) || defined(BLACKBERRY) || defined(__EMSCRIPTEN__)",
            "#   if defined(ANDROID) || defined(BLACKBERRY) || defined(__EMSCRIPTEN__) || defined(HX_PS5)"):
        changed.append("hxcpp Process.cpp")
    if edit(os.path.join(std, "Sys.cpp"),
            "#ifdef __EMSCRIPTEN__\n   #include <sys/wait.h>",
            "#if defined(__EMSCRIPTEN__) || defined(HX_PS5)\n   #include <sys/wait.h>"):
        changed.append("hxcpp Sys.cpp")

    # lime: Build.xml
    build = os.path.join(lime, "project", "Build.xml")
    for old, new in [
        ('<set name="LIME_OPENALSOFT" value="1" if="windows || linux || mac || android || ios || tvos" />',
         '<set name="LIME_OPENALSOFT" value="1" if="windows || linux || mac || android || ios || tvos || ps5" />'),
        ('<compilerflag value="-DLIME_OPENGL_GL" if="windows || mac || linux" />',
         '<compilerflag value="-DLIME_OPENGL_GL" if="windows || mac || linux || ps5" />'),
        ('<include name="lib/sdl-files.xml" />',
         '<include name="lib/sdl-files.xml" unless="ps5" />\n\t<include name="${LIME_PS5_DIR}/lime/sdl-files-ps5.xml" if="ps5" />'),
    ]:
        if edit(build, old, new):
            changed.append("lime Build.xml")

    # lime: OpenAL Soft settings for the console (it is not __linux__, so it would get none)
    openal = os.path.join(lime, "project", "lib", "custom", "openal", "include")
    platform = os.path.join(openal, "platforms", "ps5")
    os.makedirs(platform, exist_ok=True)
    for name in ("config.h", "config_backends.h"):
        shutil.copyfile(os.path.join(ps5, "lime", "openal", name), os.path.join(platform, name))
    for header in ("config.h", "config_backends.h"):
        if edit(os.path.join(openal, header),
                '#if defined(_WIN32) || defined(_WIN64) || defined(__CYGWIN__)',
                '#if defined(HX_PS5)\n    #include "platforms/ps5/' + header + '"\n#elif defined(_WIN32) || defined(_WIN64) || defined(__CYGWIN__)'):
            changed.append("lime OpenAL config")

    print("patch-libs: " + (", ".join(sorted(set(changed))) if changed else "already applied"))


if __name__ == "__main__":
    main()
