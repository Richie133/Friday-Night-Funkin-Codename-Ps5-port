/*
 * Codename Engine PS5 port - crash reports.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The console's error screen shows a single address, which is rarely enough to
 * find a cause. When the game stops on
 *  - a failed assertion (__assert: Mesa, ImGui, libunwind and the other C
 *    libraries call it), or
 *  - a fatal signal (SIGSEGV, SIGBUS, SIGILL, SIGFPE), or
 *  - std::terminate (cne_main.cpp installs cne_ps5_report_fatal for it),
 * this writes what went wrong and the call stack to the log and to
 * /data/codename-ps5/logs/crash.txt, and shows a short version as a console
 * notification before the error screen comes up.
 *
 * Addresses inside eboot.bin are written as offsets into the file ("eboot+0x1e12"),
 * which is how the symbol list published with each release
 * (PPSA52210-symbols.txt.gz) names functions.
 */

#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ucontext.h>
#include <unistd.h>

#define CRASH_FILE "/data/codename-ps5/logs/crash.txt"
#define MAX_FRAMES 32

/* tooling/native/ps5-pie.ld: the start of the image and the end of its code */
extern char __cne_image_base[] __attribute__((visibility("hidden")));
extern char __cne_text_end[] __attribute__((visibility("hidden")));

extern void cne_ps5_notify(const char *text);
extern int sceKernelUsleep(uint32_t microseconds);
extern int sceKernelGetModuleList(int *handles, size_t count, size_t *actual);
extern int sceKernelGetModuleInfo(int handle, void *info);
extern int pthread_getname_np(pthread_t thread, char *name, size_t size); /* libkernel; not in the SDK headers */

void cne_ps5_report_fatal(const char *what);

static int in_code(uintptr_t address)
{
    return address >= (uintptr_t)__cne_image_base && address < (uintptr_t)__cne_text_end;
}

/* Follows the frame-pointer chain; the console's compilers keep frame pointers.
 * Stops at the first frame that does not look right instead of guessing. */
static int walk_stack(uintptr_t frame, uintptr_t lowest, uintptr_t *out, int max)
{
    int count = 0;
    while (count < max && frame >= lowest && frame - lowest < ((uintptr_t)64 << 20) && (frame & 7) == 0) {
        const uintptr_t *slot = (const uintptr_t *)frame;
        const uintptr_t next = slot[0], address = slot[1];
        if (!in_code(address))
            break;
        out[count++] = address;
        if (next <= frame)
            break;
        frame = next;
    }
    return count;
}

/* The system module holding an address, for addresses outside eboot.bin (the
 * console's own libraries): its name and the offset into it. Uses the module info
 * layout of the system's SceKernelModuleInfo (size 0x160); best effort. */
typedef struct {
    uint64_t size;
    char name[256];
    struct {
        uint64_t address;
        uint32_t size;
        int32_t protection;
    } segments[4];
    uint32_t segment_count;
    uint8_t fingerprint[20];
} ModuleInfo;

static int module_for(uintptr_t address, char *name, size_t name_size, uintptr_t *offset)
{
    static int handles[256];
    static ModuleInfo info;
    size_t count = 0;
    if (sceKernelGetModuleList(handles, 256, &count) != 0)
        return 0;
    for (size_t i = 0; i < count && i < 256; ++i) {
        memset(&info, 0, sizeof(info));
        info.size = sizeof(info);
        if (sceKernelGetModuleInfo(handles[i], &info) != 0 || info.segment_count > 4)
            continue;
        for (uint32_t j = 0; j < info.segment_count; ++j) {
            const uintptr_t start = (uintptr_t)info.segments[j].address;
            if (address >= start && address - start < info.segments[j].size) {
                info.name[sizeof(info.name) - 1] = '\0';
                snprintf(name, name_size, "%s", info.name);
                *offset = address - (uintptr_t)info.segments[0].address;
                return 1;
            }
        }
    }
    return 0;
}

/* "eboot+0x1e12", "libkernel.sprx+0x751d0 (0x8000751d0)" or "0x8000751d0" */
static void describe(uintptr_t address, char *out, size_t size)
{
    char module[64];
    uintptr_t offset = 0;
    if (in_code(address))
        snprintf(out, size, "eboot+%#lx", (unsigned long)(address - (uintptr_t)__cne_image_base));
    else if (address != 0 && module_for(address, module, sizeof(module), &offset))
        snprintf(out, size, "%s+%#lx (%#lx)", module, (unsigned long)offset, (unsigned long)address);
    else
        snprintf(out, size, "%#lx", (unsigned long)address);
}

static char report[6144];
static size_t used;

__attribute__((format(printf, 1, 2))) static void add(const char *format, ...)
{
    if (used >= sizeof(report) - 1)
        return;
    va_list arguments;
    va_start(arguments, format);
    const int written = vsnprintf(report + used, sizeof(report) - used, format, arguments);
    va_end(arguments);
    if (written > 0)
        used += (size_t)written < sizeof(report) - used ? (size_t)written : sizeof(report) - used - 1;
}

static void add_address(const char *label, uintptr_t address)
{
    char text[128];
    describe(address, text, sizeof(text));
    add("%s%s", label, text);
}

static void add_thread(void)
{
    char name[64] = "";
    pthread_getname_np(pthread_self(), name, sizeof(name));
    add("  thread: %s\n", name[0] ? name : "(unnamed)");
}

static void add_stack(const uintptr_t *frames, int count)
{
    add("  call stack (newest first):\n");
    for (int i = 0; i < count; ++i) {
        add("    #%-2d ", i);
        add_address("", frames[i]);
        add("\n");
    }
    if (count == 0)
        add("    (not available)\n");
}

/* The first few frames for the notification, which has little room. */
static void short_stack(char *out, size_t size, const uintptr_t *frames, int count)
{
    size_t length = 0;
    out[0] = '\0';
    for (int i = 0; i < count && i < 4 && length + 24 < size; ++i) {
        const uintptr_t address = frames[i];
        char text[96];
        if (in_code(address))
            snprintf(text, sizeof(text), "%#lx", (unsigned long)(address - (uintptr_t)__cne_image_base));
        else
            describe(address, text, sizeof(text));
        length += (size_t)snprintf(out + length, size - length, i ? " %s" : "%s", text);
    }
}

static const char *base_name(const char *path)
{
    if (path == NULL)
        return "?";
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static void publish(const char *notice)
{
    FILE *log = stderr;
    fputs(report, log);
    fflush(log);
    fsync(fileno(log));
    const int file = open(CRASH_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (file >= 0) {
        (void)write(file, report, used);
        fsync(file);
        close(file);
    }
    cne_ps5_notify(notice);
    /* give the notification a moment to come up before the error screen does */
    sceKernelUsleep(2500000);
}

static volatile int reporting;

static int first_report(void)
{
    return __atomic_exchange_n(&reporting, 1, __ATOMIC_ACQ_REL) == 0;
}

/* ------------------------------------------------------------------------- */

__attribute__((noreturn)) void __assert(const char *function, const char *file, int line, const char *expression)
{
    if (first_report()) {
        uintptr_t frames[MAX_FRAMES];
        const uintptr_t here = (uintptr_t)__builtin_frame_address(0);
        const int count = walk_stack(here, here, frames, MAX_FRAMES);
        char stack[128];
        char notice[512];

        used = 0;
        add("[codename-ps5] assertion failed: %s\n", expression ? expression : "?");
        add("  in %s, %s:%d\n", function ? function : "?", file ? file : "?", line);
        add_thread();
        add_stack(frames, count);
        short_stack(stack, sizeof(stack), frames, count);
        snprintf(notice, sizeof(notice),
                 "Codename Engine stopped: assertion failed\n%.150s\n%.80s:%d (%.60s)\nat %s\n"
                 "Details: /data/codename-ps5/logs/crash.txt",
                 expression ? expression : "?", base_name(file), line, function ? function : "?", stack);
        publish(notice);
    }
    abort();
}

void cne_ps5_report_fatal(const char *what)
{
    if (!first_report())
        return;
    uintptr_t frames[MAX_FRAMES];
    const uintptr_t here = (uintptr_t)__builtin_frame_address(0);
    const int count = walk_stack(here, here, frames, MAX_FRAMES);
    char stack[128];
    char notice[512];

    used = 0;
    add("[codename-ps5] %s\n", what);
    add_thread();
    add_stack(frames, count);
    short_stack(stack, sizeof(stack), frames, count);
    snprintf(notice, sizeof(notice), "Codename Engine stopped: %.200s\nat %s\nDetails: /data/codename-ps5/logs/crash.txt",
             what, stack);
    publish(notice);
}

/*
 * Dear ImGui's checks (IM_ASSERT, see ps5-toolchain.xml): ImGui only draws Codename's
 * debug console, so a failed check is written to the log, once per place, and ImGui
 * carries on as it does in a release build. If it then really breaks, the signal
 * handler below reports that.
 */
void cne_ps5_imgui_assert(const char *expression, const char *file, int line)
{
    static struct { const char *file; int line; } seen[64];
    static int seen_count;
    for (int i = 0; i < seen_count; ++i)
        if (seen[i].line == line && seen[i].file == file)
            return;
    if (seen_count < (int)(sizeof(seen) / sizeof(seen[0]))) {
        seen[seen_count].file = file;
        seen[seen_count].line = line;
        ++seen_count;
    }
    uintptr_t frames[4];
    const uintptr_t here = (uintptr_t)__builtin_frame_address(0);
    const int count = walk_stack(here, here, frames, 4);
    fprintf(stderr, "[codename-ps5] ImGui check failed, carrying on: %s (%s:%d)", expression ? expression : "?",
            base_name(file), line);
    for (int i = 0; i < count; ++i)
        fprintf(stderr, i ? " %#lx" : " at eboot+%#lx", (unsigned long)(frames[i] - (uintptr_t)__cne_image_base));
    fputc('\n', stderr);
}

static const char *signal_name(int number)
{
    switch (number) {
    case SIGSEGV: return "SIGSEGV, bad memory access";
    case SIGBUS: return "SIGBUS, bad memory access";
    case SIGILL: return "SIGILL, bad instruction";
    case SIGFPE: return "SIGFPE, arithmetic error";
    default: return "signal";
    }
}

static void on_fatal_signal(int number, siginfo_t *info, void *context)
{
    if (first_report()) {
        const mcontext_t *registers = &((const ucontext_t *)context)->uc_mcontext;
        const uintptr_t rip = (uintptr_t)registers->mc_rip, rsp = (uintptr_t)registers->mc_rsp;
        uintptr_t frames[MAX_FRAMES];
        int count = 0;
        char stack[128];
        char notice[512];

        frames[count++] = rip;
        /* a call through a null or unloaded pointer: the caller is on top of the stack */
        if (!in_code(rip) && rsp != 0 && (rsp & 7) == 0 && in_code(*(const uintptr_t *)rsp))
            frames[count++] = *(const uintptr_t *)rsp;
        /* the stack pointer can be the broken value itself (0.1.6: rsp 0x100026c946
         * with a sound rbp): then the frame chain is followed from rbp */
        const uintptr_t rbp = (uintptr_t)registers->mc_rbp;
        const uintptr_t lowest = ((rsp & 7) == 0 && rsp <= rbp && rbp - rsp < ((uintptr_t)64 << 20)) ? rsp : rbp;
        count += walk_stack(rbp, lowest, frames + count, MAX_FRAMES - count);

        used = 0;
        add("[codename-ps5] fatal signal %d (%s), fault address %#lx\n", number, signal_name(number),
            (unsigned long)(uintptr_t)(info ? info->si_addr : NULL));
        add_thread();
        add_address("  rip ", rip);
        add("\n  rsp %#lx  rbp %#lx\n", (unsigned long)rsp, (unsigned long)registers->mc_rbp);
        add("  rax %#lx  rbx %#lx  rcx %#lx  rdx %#lx\n", (unsigned long)registers->mc_rax,
            (unsigned long)registers->mc_rbx, (unsigned long)registers->mc_rcx, (unsigned long)registers->mc_rdx);
        add("  rsi %#lx  rdi %#lx  r8 %#lx  r9 %#lx\n", (unsigned long)registers->mc_rsi,
            (unsigned long)registers->mc_rdi, (unsigned long)registers->mc_r8, (unsigned long)registers->mc_r9);
        add_stack(frames, count);
        short_stack(stack, sizeof(stack), frames, count);
        snprintf(notice, sizeof(notice), "Codename Engine crashed: %s\nfault address %#lx\nat %s\n"
                 "Details: /data/codename-ps5/logs/crash.txt",
                 signal_name(number), (unsigned long)(uintptr_t)(info ? info->si_addr : NULL), stack);
        publish(notice);
    }
    /* Back to the default action: returning re-runs the faulting instruction,
     * and the console shows its own error screen as before. */
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_DFL;
    sigemptyset(&action.sa_mask);
    sigaction(number, &action, NULL);
}

__attribute__((constructor(102))) static void install_crash_handlers(void)
{
    static const int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE };
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = on_fatal_signal;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i)
        sigaction(signals[i], &action, NULL);
}
