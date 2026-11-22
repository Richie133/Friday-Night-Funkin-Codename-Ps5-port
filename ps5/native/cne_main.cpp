// Codename Engine PS5 port - the program's entry point.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// hxcpp builds the game as a static library (static_link), which leaves main()
// to the host: this one boots hxcpp and runs the game, as hxcpp's own main does.
#include <stdio.h>

extern "C" void __hxcpp_lib_main();
extern int _hxcpp_argc;
extern char **_hxcpp_argv;

int main(int argc, char **argv)
{
    _hxcpp_argc = argc;
    _hxcpp_argv = argv;
    try {
        __hxcpp_lib_main();
    } catch (...) {
        // Lime and Codename report Haxe errors themselves; this only notes that one escaped
        fprintf(stderr, "[codename-ps5] the game stopped on an uncaught exception\n");
        fflush(stderr);
        return 1;
    }
    return 0;
}
