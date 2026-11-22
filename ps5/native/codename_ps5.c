/*
 * Codename Engine PS5 port - console glue.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Linked into eboot.bin next to the engine. It holds:
 *  - the log (stdout/stderr to /data/codename-ps5/logs/), and the main-return policy;
 *  - the size of the app heap (app_heap.c reads ps5_opengl_heap_size);
 *  - the functions funkin.ps5.PS5Native calls (browser, notifications, free space);
 *  - name lookup and socket shims a sandboxed native title needs, adapted from the
 *    ps5-native-app-boilerplate (BlackBearReloaded, GPL-3.0-or-later) and KamTape PS5:
 *    getaddrinfo / gethostbyname_r over the console's resolver and public DNS
 *    servers, and fcntl on sockets through the console's own socket option;
 *  - libc entry points the clean-room runtime does not export but the statically
 *    linked libraries (Mesa, hxcpp, SDL, OpenAL) reference.
 */

#include "dns.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/statvfs.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define CNE_DATA "/data/codename-ps5"
#define CNE_LOGS CNE_DATA "/logs"
#define CNE_LOG CNE_LOGS "/codename.log"

extern int sceKernelUsleep(uint32_t microseconds);
extern uint64_t sceKernelGetProcessTime(void);
extern int sceKernelDebugOutText(int channel, const char *text);
extern int sceSystemServiceLaunchWebBrowser(const char *uri, void *param);
extern int sceSystemServiceHideSplashScreen(void);
extern int sceSystemServiceLoadExec(const char *path, const char **argv);

/* The engine, its textures in system memory and the hxcpp heap need far more than the
 * default 128 MiB; app_heap.c takes this much from direct memory and falls back to
 * smaller sizes if the console refuses. */
const size_t ps5_opengl_heap_size = (size_t)3584u * 1024u * 1024u;
const int ps5_opengl_heap_zero_fill = 0;

/* ------------------------------------------------------------------------- */
/* Log                                                                       */

__attribute__((constructor(101))) static void cne_open_log(void)
{
    mkdir(CNE_DATA, 0777);
    mkdir(CNE_LOGS, 0777);
    rename(CNE_LOG, CNE_LOGS "/codename.prev.log");
    FILE *stream = freopen(CNE_LOG, "w", stdout);
    if (stream != NULL)
        stream = freopen(CNE_LOG, "a", stdout);
    if (stream != NULL)
        setvbuf(stream, NULL, _IONBF, 0);
    stream = freopen(CNE_LOG, "a", stderr);
    if (stream != NULL)
        setvbuf(stream, NULL, _IONBF, 0);
    printf("[codename-ps5] starting\n");
}

/* The boilerplate's CRT calls this when main returns: leave like the system expects. */
__attribute__((noreturn)) void catchReturnFromMain(int status)
{
    printf("[codename-ps5] main returned %d\n", status);
    fflush(NULL);
    sceSystemServiceLoadExec("exit", NULL);
    for (;;)
        sceKernelUsleep(100000);
}

void cne_ps5_hide_splash(void)
{
    static int hidden;
    if (!hidden) {
        hidden = 1;
        sceSystemServiceHideSplashScreen();
    }
}

/* ------------------------------------------------------------------------- */
/* Called from Haxe (funkin.ps5.PS5Native)                                   */

int cne_ps5_open_browser(const char *url)
{
    int rc = sceSystemServiceLaunchWebBrowser(url, NULL);
    printf("[codename-ps5] browser %s: 0x%x\n", url, rc);
    return rc;
}

typedef struct {
    char useless1[45];
    char message[3075];
} NotifyBuffer;

extern int sceKernelSendNotificationRequest(int device, NotifyBuffer *buffer, size_t size, int blocking);

void cne_ps5_notify(const char *text)
{
    NotifyBuffer buffer;
    memset(&buffer, 0, sizeof(buffer));
    snprintf(buffer.message, sizeof(buffer.message), "%s", text);
    sceKernelSendNotificationRequest(0, &buffer, sizeof(buffer), 0);
}

double cne_ps5_free_space(const char *path)
{
    /* statvfs: statfs itself lives in a kernel library native titles do not get */
    struct statvfs info;
    if (statvfs(path, &info) != 0)
        return -1;
    return (double)info.f_bavail * (double)info.f_frsize;
}

/* ------------------------------------------------------------------------- */
/* System libraries loaded at run time                                       */

/* Only some system libraries are loaded for a native title; importing a function
 * from another one leaves it at address 0. Those (the keyboard and mouse
 * libraries) are found or loaded here, and their functions looked up by name.
 * The approach follows KamTape PS5 and Ruffle Flash PS5. */
extern int sceKernelGetModuleList(int *handles, size_t count, size_t *actual);
extern int sceKernelGetModuleInfo(int handle, void *info);
extern int sceKernelDlsym(int handle, const char *symbol, void **address);
extern int sceKernelLoadStartModule(const char *path, size_t argc, const void *argv, uint32_t flags, void *opt, int *result);

static int find_module(const char *name)
{
    static int handles[512];
    size_t count = 0;
    if (sceKernelGetModuleList(handles, 512, &count) != 0)
        return -1;
    /* SceKernelModuleInfo's size differs between systems: try a few */
    static const uint64_t sizes[] = {0x160, 0x1a8, 0x1b0, 0x158, 0x200};
    for (size_t i = 0; i < count && i < 512; ++i) {
        for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); ++s) {
            struct {
                uint64_t size;
                char name[256];
                uint8_t rest[0x400];
            } info;
            memset(&info, 0, sizeof(info));
            info.size = sizes[s];
            if (sceKernelGetModuleInfo(handles[i], &info) != 0)
                continue;
            if (strstr(info.name, name))
                return handles[i];
            break;
        }
    }
    return -1;
}

int cne_ps5_load_module(const char *name)
{
    int handle = find_module(name);
    if (handle < 0) {
        char path[128];
        snprintf(path, sizeof(path), "/system/common/lib/%s.sprx", name);
        handle = sceKernelLoadStartModule(path, 0, NULL, 0, NULL, NULL);
    }
    fprintf(stderr, "[codename-ps5] module %s: %d\n", name, handle);
    return handle < 0 ? -1 : handle;
}

void *cne_ps5_module_symbol(int handle, const char *symbol)
{
    void *address = NULL;
    if (handle < 0 || sceKernelDlsym(handle, symbol, &address) != 0)
        return NULL;
    return address;
}

/* ------------------------------------------------------------------------- */
/* fcntl on sockets                                                          */

/* In a sandboxed title the console's libc refuses fcntl on sockets with EINVAL;
 * hxcpp's sockets use it for close-on-exec and non-blocking mode. Linked with
 * --wrap=fcntl, a refused call on a socket goes through the console's own
 * non-blocking socket option instead. */
enum { CONSOLE_SO_NBIO = 0x1200 };

extern int __real_fcntl(int descriptor, int command, ...);

static int socket_flags(int socket, int command, int value)
{
    switch (command) {
    case F_GETFD:
    case F_SETFD:
        return 0;
    case F_SETFL: {
        const int on = (value & O_NONBLOCK) != 0;
        return setsockopt(socket, SOL_SOCKET, CONSOLE_SO_NBIO, &on, sizeof(on));
    }
    case F_GETFL: {
        int on = 0;
        socklen_t length = sizeof(on);
        if (getsockopt(socket, SOL_SOCKET, CONSOLE_SO_NBIO, &on, &length) < 0)
            return -1;
        return O_RDWR | (on ? O_NONBLOCK : 0);
    }
    default:
        errno = EINVAL;
        return -1;
    }
}

int __wrap_fcntl(int descriptor, int command, ...)
{
    va_list arguments;
    va_start(arguments, command);
    const intptr_t argument = va_arg(arguments, intptr_t);
    va_end(arguments);
    const int result = __real_fcntl(descriptor, command, argument);
    if (result >= 0 || errno != EINVAL)
        return result;
    if (command == F_GETFD || command == F_SETFD || command == F_SETFL || command == F_GETFL)
        return socket_flags(descriptor, command, (int)argument);
    return result;
}

/* ------------------------------------------------------------------------- */
/* Name lookup                                                               */

extern int sceNetPoolCreate(const char *name, int size, int flags);
extern int sceNetPoolDestroy(int pool);
extern int sceNetResolverCreate(const char *name, int pool, int flags);
extern int sceNetResolverStartNtoa(int resolver, const char *hostname, struct in_addr *address,
                                   int timeout_us, int retries, int flags);
extern int sceNetResolverDestroy(int resolver);
extern int sceNetSocket(const char *name, int family, int type, int protocol);
extern int sceNetSocketClose(int socket);
extern int sceNetSetsockopt(int socket, int level, int option, const void *value, unsigned int size);
extern int sceNetSendto(int socket, const void *data, size_t length, int flags, const void *address,
                        unsigned int address_length);
extern int sceNetRecv(int socket, void *data, size_t length, int flags);

static int system_lookup(const char *name, struct in_addr *address)
{
    const int pool = sceNetPoolCreate("cne_dns", 16 * 1024, 0);
    if (pool < 0)
        return EAI_MEMORY;
    int result = EAI_FAIL;
    const int resolver = sceNetResolverCreate("cne_dns", pool, 0);
    if (resolver >= 0) {
        result = sceNetResolverStartNtoa(resolver, name, address, 5000000, 2, 0) < 0 ? EAI_NONAME : 0;
        sceNetResolverDestroy(resolver);
    }
    sceNetPoolDestroy(pool);
    return result;
}

/* Public resolvers first: on some firmware the console's resolver returns an address
 * that refuses connections for names behind CNAME aliases (found on hardware by the
 * boilerplate's apps). */
static const char *const dns_servers[] = { "1.1.1.1", "8.8.8.8", "9.9.9.9" };
enum { DNS_MAX = 4, DNS_CACHE = 32, DNS_TTL = 300 };

struct dns_entry {
    char name[128];
    uint32_t addresses[DNS_MAX];
    int count;
    time_t stored;
};

static pthread_mutex_t dns_lock = PTHREAD_MUTEX_INITIALIZER;
static struct dns_entry dns_cache[DNS_CACHE];
static int dns_next;
static int dns_unreachable;

static uint16_t dns_id(void)
{
    static uint32_t counter;
    counter = counter * 1103515245u + 12345u + (uint32_t)time(NULL) + (uint32_t)(uintptr_t)&counter;
    return (uint16_t)(counter >> 8);
}

static int dns_query(const char *server, const char *name, uint32_t *addresses, int max)
{
    uint8_t packet[DNS_MAX_PACKET];
    pthread_mutex_lock(&dns_lock);
    const uint16_t id = dns_id();
    pthread_mutex_unlock(&dns_lock);
    const int length = dns_build_query(packet, sizeof(packet), id, name);
    if (length < 0)
        return -1;
    const int fd = sceNetSocket("cne_dns", AF_INET, 2 /* DGRAM */, 0);
    if (fd < 0)
        return -1;
    const int timeout_us = 1500000;
    sceNetSetsockopt(fd, 0xffff, 0x1106 /* RCVTIMEO */, &timeout_us, sizeof(timeout_us));
    sceNetSetsockopt(fd, 0xffff, 0x1105 /* SNDTIMEO */, &timeout_us, sizeof(timeout_us));
    struct sockaddr_in to;
    memset(&to, 0, sizeof(to));
    to.sin_len = sizeof(to);
    to.sin_family = AF_INET;
    to.sin_port = htons(53);
    inet_pton(AF_INET, server, &to.sin_addr);
    int found = -1;
    if (sceNetSendto(fd, packet, (size_t)length, 0, &to, sizeof(to)) == length) {
        for (int tries = 0; tries < 4 && found == -1; ++tries) {
            const int got = sceNetRecv(fd, packet, sizeof(packet), 0);
            if (got <= 0)
                break;
            found = dns_parse_a(packet, (size_t)got, id, addresses, max);
        }
    }
    sceNetSocketClose(fd);
    return found;
}

static int own_lookup(const char *name, uint32_t *addresses)
{
    const time_t now = time(NULL);
    pthread_mutex_lock(&dns_lock);
    for (int i = 0; i < DNS_CACHE; ++i) {
        struct dns_entry *e = &dns_cache[i];
        if (e->count > 0 && strcmp(e->name, name) == 0 && now - e->stored < DNS_TTL) {
            memcpy(addresses, e->addresses, sizeof(e->addresses));
            const int count = e->count;
            pthread_mutex_unlock(&dns_lock);
            return count;
        }
    }
    const int skip = dns_unreachable;
    pthread_mutex_unlock(&dns_lock);
    if (skip || strlen(name) >= sizeof(dns_cache[0].name))
        return 0;
    int count = 0, answered = 0;
    for (int i = 0; i < 3 && count <= 0; ++i) {
        count = dns_query(dns_servers[i], name, addresses, DNS_MAX);
        if (count != -1)
            answered = 1;
    }
    pthread_mutex_lock(&dns_lock);
    if (!answered)
        dns_unreachable = 1;
    if (count > 0) {
        struct dns_entry *e = &dns_cache[dns_next];
        dns_next = (dns_next + 1) % DNS_CACHE;
        snprintf(e->name, sizeof(e->name), "%s", name);
        memset(e->addresses, 0, sizeof(e->addresses));
        memcpy(e->addresses, addresses, (size_t)count * sizeof(uint32_t));
        e->count = count;
        e->stored = now;
    }
    pthread_mutex_unlock(&dns_lock);
    return count > 0 ? count : 0;
}

static int lookup(const char *name, uint32_t *addresses, int *count)
{
    struct in_addr address;
    *count = 0;
    if (inet_pton(AF_INET, name, &address) == 1) {
        addresses[0] = address.s_addr;
        *count = 1;
        return 0;
    }
    *count = own_lookup(name, addresses);
    if (*count > 0)
        return 0;
    const int failed = system_lookup(name, &address);
    if (failed != 0)
        return failed;
    addresses[0] = address.s_addr;
    *count = 1;
    return 0;
}

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **result)
{
    *result = NULL;
    const int family = hints != NULL ? hints->ai_family : AF_UNSPEC;
    if (family != AF_UNSPEC && family != AF_INET)
        return EAI_FAMILY;
    uint32_t addresses[DNS_MAX];
    int count = 1;
    addresses[0] = htonl(INADDR_LOOPBACK);
    if (node != NULL) {
        if (hints != NULL && (hints->ai_flags & AI_NUMERICHOST) != 0) {
            struct in_addr numeric;
            if (inet_pton(AF_INET, node, &numeric) != 1)
                return EAI_NONAME;
            addresses[0] = numeric.s_addr;
        } else {
            const int failed = lookup(node, addresses, &count);
            if (failed != 0)
                return failed;
        }
    } else if (hints != NULL && (hints->ai_flags & AI_PASSIVE) != 0) {
        addresses[0] = htonl(INADDR_ANY);
    }
    struct addrinfo *head = NULL, **tail = &head;
    for (int i = 0; i < count; ++i) {
        struct addrinfo *entry = calloc(1, sizeof(struct addrinfo) + sizeof(struct sockaddr_in));
        if (entry == NULL) {
            freeaddrinfo(head);
            return EAI_MEMORY;
        }
        struct sockaddr_in *in = (struct sockaddr_in *)(entry + 1);
        in->sin_len = sizeof(*in);
        in->sin_family = AF_INET;
        in->sin_port = htons((uint16_t)(service != NULL ? atoi(service) : 0));
        in->sin_addr.s_addr = addresses[i];
        entry->ai_family = AF_INET;
        entry->ai_socktype = hints != NULL && hints->ai_socktype != 0 ? hints->ai_socktype : SOCK_STREAM;
        entry->ai_protocol = hints != NULL ? hints->ai_protocol : 0;
        entry->ai_addrlen = sizeof(*in);
        entry->ai_addr = (struct sockaddr *)in;
        *tail = entry;
        tail = &entry->ai_next;
    }
    *result = head;
    return 0;
}

void freeaddrinfo(struct addrinfo *entry)
{
    while (entry != NULL) {
        struct addrinfo *next = entry->ai_next;
        free(entry);
        entry = next;
    }
}

const char *gai_strerror(int code)
{
    switch (code) {
    case 0: return "no error";
    case EAI_NONAME: return "the name was not found";
    case EAI_FAMILY: return "address family not supported";
    case EAI_MEMORY: return "out of memory";
    default: return "the name lookup failed";
    }
}

/* hxcpp's sys.net.Host resolves with gethostbyname_r. */
int gethostbyname_r(const char *name, struct hostent *ret, char *buf, size_t buflen, struct hostent **result, int *h_errnop)
{
    uint32_t addresses[DNS_MAX];
    int count = 0;
    *result = NULL;
    if (lookup(name, addresses, &count) != 0 || count == 0) {
        if (h_errnop) *h_errnop = HOST_NOT_FOUND;
        return ENOENT;
    }
    /* buf holds: the address, the address list (2 pointers) and the name */
    size_t need = sizeof(uint32_t) + 2 * sizeof(char *) + 2 * sizeof(char *) + strlen(name) + 1;
    if (buflen < need) {
        if (h_errnop) *h_errnop = NO_RECOVERY;
        return ERANGE;
    }
    char *p = buf;
    char **list = (char **)p;
    p += 2 * sizeof(char *);
    char **aliases = (char **)p;
    p += 2 * sizeof(char *);
    uint32_t *addr = (uint32_t *)p;
    p += sizeof(uint32_t);
    *addr = addresses[0];
    list[0] = (char *)addr;
    list[1] = NULL;
    aliases[0] = NULL;
    strcpy(p, name);
    ret->h_name = p;
    ret->h_aliases = aliases;
    ret->h_addrtype = AF_INET;
    ret->h_length = 4;
    ret->h_addr_list = list;
    *result = ret;
    return 0;
}

struct hostent *gethostbyname(const char *name)
{
    static __thread struct hostent entry;
    static __thread char buffer[256];
    struct hostent *result = NULL;
    int err = 0;
    gethostbyname_r(name, &entry, buffer, sizeof(buffer), &result, &err);
    return result;
}

int getnameinfo(const struct sockaddr *address, socklen_t length, char *host, size_t host_size,
                char *service, size_t service_size, int flags)
{
    (void)flags;
    if (address == NULL || address->sa_family != AF_INET || length < sizeof(struct sockaddr_in))
        return EAI_FAMILY;
    const struct sockaddr_in *in = (const struct sockaddr_in *)address;
    if (host != NULL && host_size != 0 && inet_ntop(AF_INET, &in->sin_addr, host, (socklen_t)host_size) == NULL)
        return EAI_FAIL;
    if (service != NULL && service_size != 0)
        snprintf(service, service_size, "%u", (unsigned)ntohs(in->sin_port));
    return 0;
}

/* ------------------------------------------------------------------------- */
/* libc entry points missing from the runtime                                */

__attribute__((noreturn)) void __assert(const char *function, const char *file, int line, const char *expression)
{
    fprintf(stderr, "[codename-ps5] assertion failed: %s (%s:%d, %s)\n", expression, file, line, function);
    abort();
}

int mkstemps(char *template_name, int suffix_length)
{
    static const char letters[] = "abcdefghijklmnopqrstuvwxyz0123456789";
    static unsigned counter;
    const size_t length = template_name ? strlen(template_name) : 0;
    if (suffix_length < 0 || length < (size_t)suffix_length + 6u) {
        errno = EINVAL;
        return -1;
    }
    char *name = template_name + length - (size_t)suffix_length - 6u;
    for (int attempt = 0; attempt < 100; ++attempt) {
        uint64_t value = sceKernelGetProcessTime() + (uint64_t)__atomic_add_fetch(&counter, 1u, __ATOMIC_RELAXED) * UINT64_C(0x9E3779B97F4A7C15);
        for (int i = 0; i < 6; ++i) {
            name[i] = letters[value % 36u];
            value /= 36u;
        }
        const int file = open(template_name, O_RDWR | O_CREAT | O_EXCL, 0600);
        if (file >= 0 || errno != EEXIST)
            return file;
    }
    errno = EEXIST;
    return -1;
}

int mkstemp(char *template_name) { return mkstemps(template_name, 0); }

int isatty(int descriptor)
{
    (void)descriptor;
    errno = ENOTTY;
    return 0;
}

void openlog(const char *identifier, int option, int facility)
{
    (void)identifier;
    (void)option;
    (void)facility;
}

FILE *popen(const char *command, const char *mode)
{
    (void)command;
    (void)mode;
    errno = ENOSYS;
    return NULL;
}

int pclose(FILE *stream)
{
    (void)stream;
    errno = ENOSYS;
    return -1;
}

/* Reentrant time functions the console's libc does not export (Lua's os.date,
 * hxcpp's Date). Weak, in case a library brings its own. */
static pthread_mutex_t time_lock = PTHREAD_MUTEX_INITIALIZER;

__attribute__((weak)) struct tm *localtime_r(const time_t *timer, struct tm *result)
{
    pthread_mutex_lock(&time_lock);
    struct tm *value = localtime(timer);
    if (value) *result = *value;
    pthread_mutex_unlock(&time_lock);
    return value ? result : NULL;
}

__attribute__((weak)) struct tm *gmtime_r(const time_t *timer, struct tm *result)
{
    pthread_mutex_lock(&time_lock);
    struct tm *value = gmtime(timer);
    if (value) *result = *value;
    pthread_mutex_unlock(&time_lock);
    return value ? result : NULL;
}

__attribute__((weak)) time_t timegm(struct tm *tm)
{
    /* days from 1970-01-01 to the given date (proleptic Gregorian) */
    long long year = tm->tm_year + 1900LL, month = tm->tm_mon;
    year += month / 12;
    month %= 12;
    if (month < 0) { month += 12; --year; }
    static const int before[12] = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334};
    long long days = (year - 1970) * 365 + before[month] + tm->tm_mday - 1;
    long long y = month < 2 ? year - 1 : year; /* leap days up to the date */
    days += (y / 4 - y / 100 + y / 400) - (1969 / 4 - 1969 / 100 + 1969 / 400);
    return (time_t)(((days * 24 + tm->tm_hour) * 60 + tm->tm_min) * 60 + tm->tm_sec);
}

/* No temporary-file service: Lua's io.tmpfile and os.tmpname use the cache folder */
__attribute__((weak)) FILE *tmpfile(void)
{
    char name[] = "/data/codename-ps5/cache/tmp-XXXXXX";
    int file = mkstemp(name);
    if (file < 0) return NULL;
    unlink(name);
    return fdopen(file, "w+b");
}

__attribute__((weak)) char *tmpnam(char *buffer)
{
    static char name[64];
    static unsigned counter;
    char *out = buffer ? buffer : name;
    snprintf(out, 64, "/data/codename-ps5/cache/tmp-%llu-%u", (unsigned long long)sceKernelGetProcessTime(),
             __atomic_add_fetch(&counter, 1u, __ATOMIC_RELAXED));
    return out;
}

/* Mesa's per-thread GL context holder: initialised statically in this build */
void cne_glapi_tls_context_init(void) __asm__("_ZTH23_mesa_glapi_tls_Context");
void cne_glapi_tls_context_init(void) {}
