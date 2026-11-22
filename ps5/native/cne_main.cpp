// Codename Engine PS5 port - the program's entry point.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// hxcpp builds the game as a static library (static_link), which leaves main()
// to the host: this one boots hxcpp and runs the game, as hxcpp's own main does.
#include <exception>
#include <stdio.h>
#include <stdlib.h>

extern "C" void __hxcpp_lib_main();
extern "C" void cne_ps5_report_fatal(const char *what); // crash_report.c
extern int _hxcpp_argc;
extern char **_hxcpp_argv;

[[noreturn]] static void on_terminate()
{
    cne_ps5_report_fatal("std::terminate: a C++ exception was not caught, or could not be unwound");
    abort();
}

int main(int argc, char **argv)
{
    _hxcpp_argc = argc;
    _hxcpp_argv = argv;
    std::set_terminate(on_terminate);
    fprintf(stderr, "[codename-ps5] main: starting the engine\n");
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
