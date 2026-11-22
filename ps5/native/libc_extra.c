/*
 * Codename Engine PS5 port - C library pieces the console does not export.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The payload SDK's libc++ is built against FreeBSD's per-locale API (strtod_l,
 * __runes_for_locale, newlocale...), which the console's libc does not export.
 * The game only ever uses the "C" locale, so each function here does what its
 * plain counterpart does, ignoring the locale argument. Also: a few POSIX calls
 * that libraries reference but the console lacks (catalogs, utimensat, times,
 * getpwuid, gethostbyaddr_r, cfmakeraw), thread_local destructors for libc++abi,
 * zstd's optional tracing hooks, and the few file calls (openat, statfs...) the
 * SDK puts in libkernel_sys, a kernel library native titles do not get: importing
 * them would leave them at address 0, so they are rebuilt here from the ones
 * libkernel has.
 */
#define _XLOCALE_INLINE_ONLY_DECLARATIONS
#include <errno.h>
#include <fcntl.h>
#include <langinfo.h>
#include <limits.h>
#include <locale.h>
#include <netdb.h>
#include <pthread.h>
#include <nl_types.h>
#include <pwd.h>
#include <runetype.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/time.h>
#include <sys/times.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <wchar.h>
#include <wctype.h>
#include <xlocale.h>


/* ---- locale objects: one stand-in for every locale */

static int c_locale_object;

locale_t newlocale(int mask, const char *name, locale_t base)
{
    (void)mask;
    (void)name;
    (void)base;
    return (locale_t)&c_locale_object;
}

int freelocale(locale_t locale)
{
    (void)locale;
    return 0;
}

locale_t uselocale(locale_t locale)
{
    (void)locale;
    return LC_GLOBAL_LOCALE;
}

struct lconv *localeconv_l(locale_t locale)
{
    (void)locale;
    return localeconv();
}

char *nl_langinfo(nl_item item)
{
    switch (item) {
    case CODESET: return (char *)"US-ASCII";
    case RADIXCHAR: return (char *)".";
    case THOUSEP: return (char *)"";
    case D_T_FMT: return (char *)"%a %b %e %H:%M:%S %Y";
    case D_FMT: return (char *)"%m/%d/%y";
    case T_FMT: return (char *)"%H:%M:%S";
    case T_FMT_AMPM: return (char *)"%I:%M:%S %p";
    case AM_STR: return (char *)"AM";
    case PM_STR: return (char *)"PM";
    case YESEXPR: return (char *)"^[yY]";
    case NOEXPR: return (char *)"^[nN]";
    default: return (char *)"";
    }
}

/* ---- character classes (the C locale's table from the console's libc) */

_RuneLocale *__runes_for_locale(locale_t locale, int *limit)
{
    (void)locale;
    if (limit) *limit = 256;
    return (_RuneLocale *)&_DefaultRuneLocale;
}

unsigned long ___runetype_l(__ct_rune_t c, locale_t locale)
{
    (void)locale;
    return (c >= 0 && c < 256) ? _DefaultRuneLocale.__runetype[c] : 0;
}

__ct_rune_t ___tolower_l(__ct_rune_t c, locale_t locale)
{
    (void)locale;
    return (c >= 0 && c < 256) ? _DefaultRuneLocale.__maplower[c] : c;
}

__ct_rune_t ___toupper_l(__ct_rune_t c, locale_t locale)
{
    (void)locale;
    return (c >= 0 && c < 256) ? _DefaultRuneLocale.__mapupper[c] : c;
}

int ___mb_cur_max(void) { return 1; }

int ___mb_cur_max_l(locale_t locale)
{
    (void)locale;
    return 1;
}

int iswctype_l(wint_t c, wctype_t type, locale_t locale)
{
    /* (the SDK's iswctype is inline and needs functions the console lacks) */
    (void)locale;
    return c < 256 ? (_DefaultRuneLocale.__runetype[c] & type) != 0 : 0;
}

/* ---- numbers */

long long strtoll_l(const char *s, char **end, int base, locale_t l) { (void)l; return strtoll(s, end, base); }
unsigned long long strtoull_l(const char *s, char **end, int base, locale_t l) { (void)l; return strtoull(s, end, base); }
float strtof_l(const char *s, char **end, locale_t l) { (void)l; return strtof(s, end); }
double strtod_l(const char *s, char **end, locale_t l) { (void)l; return strtod(s, end); }
long double strtold_l(const char *s, char **end, locale_t l) { (void)l; return strtold(s, end); }

int sscanf_l(const char *s, locale_t l, const char *format, ...)
{
    (void)l;
    va_list args;
    va_start(args, format);
    int n = vsscanf(s, format, args);
    va_end(args);
    return n;
}

int snprintf_l(char *out, size_t size, locale_t l, const char *format, ...)
{
    (void)l;
    va_list args;
    va_start(args, format);
    int n = vsnprintf(out, size, format, args);
    va_end(args);
    return n;
}

int asprintf_l(char **out, locale_t l, const char *format, ...)
{
    (void)l;
    va_list args;
    va_start(args, format);
    int n = vasprintf(out, format, args);
    va_end(args);
    return n;
}

/* ---- strings and time */

int strcoll_l(const char *a, const char *b, locale_t l) { (void)l; return strcoll(a, b); }
size_t strxfrm_l(char *dst, const char *src, size_t n, locale_t l) { (void)l; return strxfrm(dst, src, n); }
int wcscoll_l(const wchar_t *a, const wchar_t *b, locale_t l) { (void)l; return wcscoll(a, b); }
size_t wcsxfrm_l(wchar_t *dst, const wchar_t *src, size_t n, locale_t l) { (void)l; return wcsxfrm(dst, src, n); }

size_t strftime_l(char *out, size_t size, const char *format, const struct tm *tm, locale_t l)
{
    (void)l;
    return strftime(out, size, format, tm);
}

/* ---- multibyte */

wint_t btowc_l(int c, locale_t l) { (void)l; return btowc(c); }
int wctob_l(wint_t c, locale_t l) { (void)l; return wctob(c); }
int mbtowc_l(wchar_t *wc, const char *s, size_t n, locale_t l) { (void)l; return mbtowc(wc, s, n); }
size_t mbrtowc_l(wchar_t *wc, const char *s, size_t n, mbstate_t *ps, locale_t l) { (void)l; return mbrtowc(wc, s, n, ps); }
size_t mbrlen_l(const char *s, size_t n, mbstate_t *ps, locale_t l) { (void)l; return mbrlen(s, n, ps); }
size_t wcrtomb_l(char *s, wchar_t wc, mbstate_t *ps, locale_t l) { (void)l; return wcrtomb(s, wc, ps); }

size_t mbsrtowcs_l(wchar_t *dst, const char **src, size_t len, mbstate_t *ps, locale_t l)
{
    (void)l;
    return mbsrtowcs(dst, src, len, ps);
}

/* mbsnrtowcs and wcsnrtombs are missing from the console's libc too */
size_t mbsnrtowcs_l(wchar_t *dst, const char **src, size_t nms, size_t len, mbstate_t *ps, locale_t l)
{
    (void)l;
    static mbstate_t own;
    if (!ps) ps = &own;
    const char *s = *src;
    size_t count = 0;
    while (nms > 0 && (!dst || count < len)) {
        wchar_t wc;
        size_t used = mbrtowc(&wc, s, nms, ps);
        if (used == (size_t)-1) {
            *src = s;
            return (size_t)-1;
        }
        if (used == (size_t)-2) break; /* incomplete character at the end */
        if (used == 0) { /* the terminating null */
            if (dst) dst[count] = 0;
            *src = NULL;
            return count;
        }
        if (dst) dst[count] = wc;
        count++;
        s += used;
        nms -= used;
    }
    if (dst) *src = s;
    return count;
}

size_t wcsnrtombs_l(char *dst, const wchar_t **src, size_t nwc, size_t len, mbstate_t *ps, locale_t l)
{
    (void)l;
    static mbstate_t own;
    if (!ps) ps = &own;
    const wchar_t *s = *src;
    size_t count = 0;
    char buffer[MB_LEN_MAX];
    while (nwc > 0) {
        size_t n = wcrtomb(buffer, *s, ps);
        if (n == (size_t)-1) {
            *src = s;
            return (size_t)-1;
        }
        if (dst && count + n > len) break;
        if (dst) memcpy(dst + count, buffer, n);
        if (*s == 0) {
            if (dst) *src = NULL;
            return count;
        }
        count += n;
        s++;
        nwc--;
    }
    if (dst) *src = s;
    return count;
}

size_t mbsnrtowcs(wchar_t *dst, const char **src, size_t nms, size_t len, mbstate_t *ps)
{
    return mbsnrtowcs_l(dst, src, nms, len, ps, NULL);
}

size_t wcsnrtombs(char *dst, const wchar_t **src, size_t nwc, size_t len, mbstate_t *ps)
{
    return wcsnrtombs_l(dst, src, nwc, len, ps, NULL);
}

/* ---- message catalogs: none */

nl_catd catopen(const char *name, int flag)
{
    (void)name;
    (void)flag;
    errno = ENOENT;
    return (nl_catd)-1;
}

char *catgets(nl_catd catalog, int set, int number, const char *fallback)
{
    (void)catalog;
    (void)set;
    (void)number;
    return (char *)fallback;
}

int catclose(nl_catd catalog)
{
    (void)catalog;
    return 0;
}

/* ---- files, processes, users, network, terminals */

int utimensat(int dirfd, const char *path, const struct timespec times[2], int flag)
{
    (void)flag;
    if (dirfd != AT_FDCWD || path == NULL) {
        errno = ENOSYS;
        return -1;
    }
    if (times == NULL) return utimes(path, NULL);
    struct timeval tv[2];
    for (int i = 0; i < 2; i++) {
        tv[i].tv_sec = times[i].tv_sec;
        tv[i].tv_usec = times[i].tv_nsec / 1000;
    }
    return utimes(path, tv);
}

clock_t times(struct tms *buffer)
{
    clock_t now = clock();
    if (buffer) {
        buffer->tms_utime = now;
        buffer->tms_stime = 0;
        buffer->tms_cutime = 0;
        buffer->tms_cstime = 0;
    }
    return now;
}

struct passwd *getpwuid(uid_t uid)
{
    (void)uid;
    return NULL;
}

int gethostbyaddr_r(const void *address, socklen_t length, int type, struct hostent *entry, char *buffer, size_t size,
                    struct hostent **result, int *error)
{
    (void)address;
    (void)length;
    (void)type;
    (void)entry;
    (void)buffer;
    (void)size;
    if (result) *result = NULL;
    if (error) *error = HOST_NOT_FOUND;
    return ENOENT;
}

void cfmakeraw(struct termios *t)
{
    t->c_iflag &= ~(IMAXBEL | IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    t->c_oflag &= ~OPOST;
    t->c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    t->c_cflag &= ~(CSIZE | PARENB);
    t->c_cflag |= CS8;
}

/* ---- thread_local destructors (libc++abi asks for this; the console's libc has none) */

typedef struct thread_dtor {
    void (*fn)(void *);
    void *object;
    struct thread_dtor *next;
} thread_dtor;

static pthread_key_t dtor_key;
static pthread_once_t dtor_once = PTHREAD_ONCE_INIT;

static void run_thread_dtors(void *list)
{
    thread_dtor *d = list;
    while (d) {
        thread_dtor *next = d->next;
        d->fn(d->object);
        free(d);
        d = next;
    }
}

static void make_dtor_key(void) { pthread_key_create(&dtor_key, run_thread_dtors); }

int __cxa_thread_atexit_impl(void (*fn)(void *), void *object, void *dso)
{
    (void)dso;
    pthread_once(&dtor_once, make_dtor_key);
    thread_dtor *d = malloc(sizeof *d);
    if (!d) return -1;
    d->fn = fn;
    d->object = object;
    d->next = pthread_getspecific(dtor_key);
    pthread_setspecific(dtor_key, d);
    return 0;
}

/* ---- zstd (inside libarchive) declares tracing hooks weak; tracing stays off */

unsigned long long ZSTD_trace_decompress_begin(const void *context)
{
    (void)context;
    return 0;
}

void ZSTD_trace_decompress_end(unsigned long long context, const void *trace)
{
    (void)context;
    (void)trace;
}

/* ---- libkernel_sys's file calls, from libkernel's (paths relative to the
 * current directory only: nothing here uses directory descriptors) */

static int at_cwd(int dirfd, const char *path)
{
    if (dirfd == AT_FDCWD || (path && path[0] == '/')) return 1;
    errno = ENOSYS;
    return 0;
}

int openat(int dirfd, const char *path, int flags, ...)
{
    int mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = va_arg(args, int);
        va_end(args);
    }
    return at_cwd(dirfd, path) ? open(path, flags, mode) : -1;
}

int unlinkat(int dirfd, const char *path, int flag)
{
    if (!at_cwd(dirfd, path)) return -1;
    return (flag & AT_REMOVEDIR) ? rmdir(path) : unlink(path);
}

int fchmodat(int dirfd, const char *path, mode_t mode, int flag)
{
    (void)flag;
    return at_cwd(dirfd, path) ? chmod(path, mode) : -1;
}

ssize_t readlink(const char *path, char *buffer, size_t size)
{
    (void)path;
    (void)buffer;
    (void)size;
    errno = EINVAL; /* no symbolic links on the console's data partition */
    return -1;
}

int symlink(const char *target, const char *path)
{
    (void)target;
    (void)path;
    errno = ENOSYS;
    return -1;
}

int link(const char *target, const char *path)
{
    (void)target;
    (void)path;
    errno = ENOSYS;
    return -1;
}

long pathconf(const char *path, int name)
{
    (void)path;
    switch (name) {
    case _PC_NAME_MAX: return 255;
    case _PC_PATH_MAX: return 1024;
    default: errno = EINVAL; return -1;
    }
}

pid_t fork(void)
{
    errno = ENOSYS;
    return -1;
}

int statfs(const char *path, struct statfs *out)
{
    struct statvfs info;
    if (statvfs(path, &info) != 0) return -1;
    memset(out, 0, sizeof(*out));
    out->f_bsize = info.f_frsize;
    out->f_iosize = info.f_bsize;
    out->f_blocks = info.f_blocks;
    out->f_bfree = info.f_bfree;
    out->f_bavail = info.f_bavail;
    out->f_files = info.f_files;
    out->f_ffree = info.f_ffree;
    return 0;
}
