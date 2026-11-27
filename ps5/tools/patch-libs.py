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
         lib/glad-files.xml                GLAD's GL loader on -Dps5
         lib/custom/openal/include         OpenAL Soft settings for the console
                                           (ps5/lime/openal)
         lib/imgui/backends/               Dear ImGui's GL loader takes GL functions
           imgui_impl_opengl3_loader.h     from EGL on the console (no libGL to dlopen)
         src/backend/sdl/SDLWindow.cpp     logs a failed ImGui renderer start
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


def append_once(path, marker, text):
    with open(path, encoding="utf-8") as f:
        current = f.read()
    if marker in current:
        return False
    with open(path, "a", encoding="utf-8") as f:
        f.write(text)
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

    # lime: GLAD's desktop GL loader (gl.c) on the console too
    if edit(os.path.join(lime, "project", "lib", "glad-files.xml"),
            '<file name="${NATIVE_TOOLKIT_PATH}/glad/src/gl.c" if="windows || mac || linux" />',
            '<file name="${NATIVE_TOOLKIT_PATH}/glad/src/gl.c" if="windows || mac || linux || ps5" />'):
        changed.append("lime glad-files.xml")

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

    # lime: Dear ImGui's OpenGL loader (gl3w) dlopen()s libGL, which the console does
    # not have: its renderer backend never started and the first frame stopped on
    # ImGui_ImplOpenGL3_NewFrame's assertion. ps5-opengl is linked in, and EGL hands
    # out every GL entry point.
    if edit(os.path.join(lime, "project", "lib", "imgui", "backends", "imgui_impl_opengl3_loader.h"),
            "#elif defined(__APPLE__)\n#include <dlfcn.h>\n\nstatic void *libgl = NULL;",
            "#elif defined(__PROSPERO__)\n"
            "/* PS5 (Codename Engine port): the GL driver is linked into the app; ask EGL. */\n"
            "typedef void (*imgl3w_egl_proc)(void);\n"
            "imgl3w_egl_proc eglGetProcAddress(const char *procname);\n"
            "static int open_libgl(void) { return GL3W_OK; }\n"
            "static void close_libgl(void) {}\n"
            "static GL3WglProc get_proc(const char *proc) { return (GL3WglProc)eglGetProcAddress(proc); }\n"
            "#elif defined(__APPLE__)\n#include <dlfcn.h>\n\nstatic void *libgl = NULL;",
            marker="#elif defined(__PROSPERO__)\n/* PS5 (Codename Engine port)"):
        changed.append("lime ImGui GL loader")
    # hxcpp's compile cache keys an object on its .cpp and not on the headers it
    # includes: change the backend's .cpp too, so no object built before is reused
    if edit(os.path.join(lime, "project", "lib", "imgui", "backends", "imgui_impl_opengl3.cpp"),
            "#define IMGL3W_IMPL\n#define IMGUI_IMPL_OPENGL_LOADER_IMGL3W\n",
            "#define IMGL3W_IMPL // PS5 port: on __PROSPERO__ the loader asks EGL for GL functions\n"
            "#define IMGUI_IMPL_OPENGL_LOADER_IMGL3W\n"):
        changed.append("lime ImGui GL backend")
    # lime: the console has one window, so no ImGui multi-viewport (ImGui switches it
    # off on frame 0 anyway, and it must not be switched back on: see Options.hx)
    if edit(os.path.join(lime, "project", "src", "backend", "sdl", "SDLWindow.cpp"),
            "\t\t\t\tio.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;\n",
            "\t\t\t\t#ifndef __PROSPERO__ // PS5 port: one window only\n"
            "\t\t\t\tio.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;\n"
            "\t\t\t\t#endif\n"):
        changed.append("lime SDLWindow")
    # lime: on the console a failed ImGui check is logged and ImGui carries on, as in a
    # release build, so the debug console cannot end the game. ps5-toolchain.xml
    # defines CNE_PS5_IMGUI_SOFT_ASSERT (a compiler flag, so that hxcpp's compile
    # cache, which does not look at headers, rebuilds everything that includes ImGui).
    if append_once(os.path.join(lime, "project", "lib", "imgui", "imconfig.h"),
                   "CNE_PS5_IMGUI_SOFT_ASSERT",
                   "\n// PS5 (Codename Engine port): log a failed check and carry on (crash_report.c)\n"
                   "#if defined(CNE_PS5_IMGUI_SOFT_ASSERT)\n"
                   "#ifdef __cplusplus\nextern \"C\"\n#endif\n"
                   "void cne_ps5_imgui_assert(const char *expression, const char *file, int line);\n"
                   "#define IM_ASSERT(_EXPR) ((_EXPR) ? (void)0 : cne_ps5_imgui_assert(#_EXPR, __FILE__, __LINE__))\n"
                   "#endif\n"):
        changed.append("lime ImGui config")
    # ... and say so in the log if the ImGui renderer backend still cannot start
    if edit(os.path.join(lime, "project", "src", "backend", "sdl", "SDLWindow.cpp"),
            '\t\t\t\tImGui_ImplOpenGL3_Init("#version 150");',
            '\t\t\t\tif (!ImGui_ImplOpenGL3_Init("#version 150")) printf("[lime] the ImGui OpenGL backend did not start\\n");'):
        changed.append("lime SDLWindow")

    print("patch-libs: " + (", ".join(sorted(set(changed))) if changed else "already applied"))


if __name__ == "__main__":
    main()
