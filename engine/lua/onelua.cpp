/*
 * Lua 5.1.5 in one file, for the PS5 port's Psych Engine Lua layer
 * (funkin.ps5.psych.LuaBridge adds this file to the hxcpp build).
 *
 * Compiled as C++ on purpose: Lua then raises its errors with C++ exceptions
 * instead of longjmp, which is safe to unwind through hxcpp's frames.
 * Based on etc/all.c from the Lua 5.1.5 distribution (MIT, see COPYRIGHT).
 */

/* Not luaall_c (its "static const" declarations are not valid C++), so the parts of
 * luaconf.h that only the io and os libraries see are asked for by name here. */
#define liolib_c
#define loslib_c

/* system headers first: ldebug.h defines a getline() macro that clashes with stdio's */
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lapi.c"
#include "lcode.c"
#include "ldebug.c"
#include "ldo.c"
#include "ldump.c"
#include "lfunc.c"
#include "lgc.c"
#include "llex.c"
#include "lmem.c"
#include "lobject.c"
#include "lopcodes.c"
#include "lparser.c"
#include "lstate.c"
#include "lstring.c"
#include "ltable.c"
#include "ltm.c"
#include "lundump.c"
#include "lvm.c"
#include "lzio.c"

#include "lauxlib.c"
#include "lbaselib.c"
#include "ldblib.c"
#include "liolib.c"
#include "linit.c"
#include "lmathlib.c"
#include "loadlib.c"
#include "loslib.c"
#include "lstrlib.c"
#include "ltablib.c"
