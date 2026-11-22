/* OpenAL Soft build settings for the PS5 port (Lime's openal, platforms/ps5). */
/* Audio goes out through SDL3 (the port's SDL audio driver uses sceAudioOut). */

/* Define the alignment attribute for externally callable functions. */
#define FORCE_ALIGN

/* Define if HRTF data is embedded in the library */
#define ALSOFT_EMBED_HRTF_DATA

/* Define if we have cpuid.h */
#define HAVE_CPUID_H

/* Define if we have GCC's __get_cpuid() */
#define HAVE_GCC_GET_CPUID

/* Define to 1 if we have C++20 modules, else 0 */
#define HAVE_CXXMODULES 0

/* No DBus/RTKit, and nothing is loaded at run time on the console */
#define HAVE_RTKIT 0
#define HAVE_DYNLOAD 0

/* Define to 1 if building for winuwp, else 0 */
#define ALSOFT_UWP 0

/* Define to 1 if building with legacy EAX API support, else 0 */
#define ALSOFT_EAX 0
