/*
  SDL3 build configuration for the PlayStation 5 (homebrew, ps5-payload-sdk + ps5-opengl).
  Part of the Codename Engine PS5 port. zlib license, like SDL itself.

  SDL3 keeps a "private platform" slot for console ports: SDL_PLATFORM_PRIVATE,
  PRIVATE_bootstrap (video), PRIVATEAUDIO_bootstrap (audio) and
  SDL_PRIVATE_JoystickDriver. ps5/sdl/SDL_ps5.c fills those slots, so SDL itself
  is built unchanged.
*/
#ifndef SDL_build_config_private_h_
#define SDL_build_config_private_h_

#define SDL_PLATFORM_PRIVATE_NAME "PlayStation 5"

#define HAVE_LIBC 1
#define HAVE_GCC_ATOMICS 1
#define HAVE_GCC_SYNC_LOCK_TEST_AND_SET 1

#define HAVE_STDARG_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 1
#define HAVE_FLOAT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MATH_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_WCHAR_H 1
#define HAVE_MALLOC 1
#define HAVE_ABS 1
#define HAVE_MEMCMP 1
#define HAVE_MEMCPY 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_STRLEN 1
#define HAVE_STRNLEN 1
#define HAVE_STRCHR 1
#define HAVE_STRRCHR 1
#define HAVE_STRSTR 1
#define HAVE_STRTOK_R 1
#define HAVE_STRTOL 1
#define HAVE_STRTOUL 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOULL 1
#define HAVE_STRTOD 1
#define HAVE_ATOI 1
#define HAVE_ATOF 1
#define HAVE_STRCMP 1
#define HAVE_STRNCMP 1
#define HAVE_VSSCANF 1
#define HAVE_VSNPRINTF 1
#define HAVE_QSORT 1
#define HAVE_BSEARCH 1
#define HAVE_ACOS 1
#define HAVE_ACOSF 1
#define HAVE_ASIN 1
#define HAVE_ASINF 1
#define HAVE_ATAN 1
#define HAVE_ATANF 1
#define HAVE_ATAN2 1
#define HAVE_ATAN2F 1
#define HAVE_CEIL 1
#define HAVE_CEILF 1
#define HAVE_COPYSIGN 1
#define HAVE_COPYSIGNF 1
#define HAVE_COS 1
#define HAVE_COSF 1
#define HAVE_EXP 1
#define HAVE_EXPF 1
#define HAVE_FABS 1
#define HAVE_FABSF 1
#define HAVE_FLOOR 1
#define HAVE_FLOORF 1
#define HAVE_FMOD 1
#define HAVE_FMODF 1
#define HAVE_ISINF 1
#define HAVE_ISNAN 1
#define HAVE_LOG 1
#define HAVE_LOGF 1
#define HAVE_LOG10 1
#define HAVE_LOG10F 1
#define HAVE_LROUND 1
#define HAVE_LROUNDF 1
#define HAVE_MODF 1
#define HAVE_MODFF 1
#define HAVE_POW 1
#define HAVE_POWF 1
#define HAVE_ROUND 1
#define HAVE_ROUNDF 1
#define HAVE_SCALBN 1
#define HAVE_SCALBNF 1
#define HAVE_SIN 1
#define HAVE_SINF 1
#define HAVE_SQRT 1
#define HAVE_SQRTF 1
#define HAVE_TAN 1
#define HAVE_TANF 1
#define HAVE_TRUNC 1
#define HAVE_TRUNCF 1
#define HAVE_NANOSLEEP 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_GMTIME_R 1
#define HAVE_LOCALTIME_R 1
#define HAVE_SYSCONF 1

/* Threads, timers and time come from the console's POSIX layer (libkernel). */
#define SDL_THREAD_PTHREAD 1
#define SDL_THREAD_PTHREAD_RECURSIVE_MUTEX 1
#define SDL_TIMER_UNIX 1
#define SDL_TIME_UNIX 1
#define SDL_FSOPS_POSIX 1

/* The port's drivers (ps5/sdl/SDL_ps5.c) */
#define SDL_VIDEO_DRIVER_PRIVATE 1
#define SDL_AUDIO_DRIVER_PRIVATE 1
#define SDL_JOYSTICK_PRIVATE 1
/* the driver gives SDL its button layout (PS5_JoystickGetGamepadMapping), so no database entries */
#define SDL_PRIVATE_GAMEPAD_DEFINITIONS
#define SDL_FILESYSTEM_PRIVATE 1

/* OpenGL 4.6 / compatibility through ps5-opengl's EGL; no GLES or Vulkan here. */
#define SDL_VIDEO_OPENGL 1
#define SDL_VIDEO_RENDER_OGL 1
#define SDL_VIDEO_RENDER_SW 1

/* What the console has none of, or the port does not use. */
#define SDL_LOADSO_DUMMY 1
#define SDL_HAPTIC_DUMMY 1
#define SDL_SENSOR_DUMMY 1
#define SDL_CAMERA_DRIVER_DUMMY 1
#define SDL_DIALOG_DUMMY 1
#define SDL_PROCESS_DUMMY 1
#define SDL_TRAY_DUMMY 1
#define SDL_HIDAPI_DISABLED 1
#define SDL_JOYSTICK_HIDAPI_DISABLED 1
#define SDL_GPU_DISABLED 1
#define SDL_POWER_DISABLED 1

#endif /* SDL_build_config_private_h_ */
