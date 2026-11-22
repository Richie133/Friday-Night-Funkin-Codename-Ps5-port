/*
  SDL3 platform drivers for the PlayStation 5 (homebrew).
  Part of the Codename Engine PS5 port: https://github.com/Richie133/Friday-Night-Funkin-Codename-Ps5-port

  SPDX-License-Identifier: GPL-3.0-or-later (it adapts code from ps5-opengl, which is
  GPL-3.0-or-later; see THIRD_PARTY_NOTICES.md).

  Fills SDL3's private-platform slots:

    video     PRIVATE_bootstrap        one full-screen window drawn with OpenGL through
                                       ps5-opengl's EGL (1080p, 1440p or 4K at 60/120 Hz,
                                       picked from /data/codename-ps5/display.cfg)
    events                             USB/Bluetooth keyboards (libSceKeyboard), mice
                                       (libSceMouse, when the system has it) and the
                                       DualSense touchpad as a pointer
    joystick  SDL_PRIVATE_JoystickDriver  DualSense controllers of the signed-in users
                                       (libScePad), touchpad included
    audio     PRIVATEAUDIO_bootstrap   48 kHz stereo through libSceAudioOut
    files     SDL_SYS_GetBasePath ...  /app0/ for the app, /data/codename-ps5/ for saves

  The driver logic for the pad, audio and keyboard follows ps5-payload-dev/SDL (SDL2,
  John Tornblom, zlib); the EGL set-up follows ps5-opengl's SDL2 bridge (BlackBearReloaded).
*/
#include "SDL_internal.h"

#include "video/SDL_sysvideo.h"
#include "events/SDL_keyboard_c.h"
#include "events/SDL_mouse_c.h"
#include "joystick/SDL_sysjoystick.h"
#include "joystick/SDL_joystick_c.h"
#include "audio/SDL_sysaudio.h"
#include "filesystem/SDL_sysfilesystem.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#if __has_include(<ps5_opengl_display_modes.h>)
#include <ps5_opengl_display_modes.h>
#define CNE_PS5_DYNAMIC_DISPLAY 1
#endif

#define CNE_PS5_DATA "/data/codename-ps5/"

/* ------------------------------------------------------------------------- */
/* System functions (stubs from the payload SDK resolve them at load time)   */

typedef struct PS5_PadTouch {
    uint16_t x;
    uint16_t y;
    uint8_t finger;
    uint8_t pad[3];
} PS5_PadTouch;

typedef struct PS5_PadTouchData {
    uint8_t fingers;
    uint8_t pad1[3];
    uint32_t pad2;
    PS5_PadTouch touch[2];
} PS5_PadTouchData;

typedef struct PS5_PadData {
    uint32_t buttons;
    struct { uint8_t x, y; } leftStick;
    struct { uint8_t x, y; } rightStick;
    struct { uint8_t l2, r2; } analogButtons;
    uint16_t padding;
    struct { float x, y, z, w; } quat;
    struct { float x, y, z; } vel;
    struct { float x, y, z; } acell;
    PS5_PadTouchData touch;
    uint8_t connected;
    uint64_t timestamp;
    uint8_t ext[16];
    uint8_t count;
    uint8_t unknown[15];
} PS5_PadData;

typedef struct PS5_PadColor { uint8_t r, g, b, a; } PS5_PadColor;
typedef struct PS5_PadVibration { uint8_t large_motor, small_motor; } PS5_PadVibration;

int scePadInit(void);
int scePadOpen(int user_id, int type, int index, void *param);
int scePadReadState(int handle, PS5_PadData *data);
int scePadSetLightBar(int handle, const PS5_PadColor *color);
int scePadSetVibrationMode(int handle, int mode);
int scePadSetVibration(int handle, const PS5_PadVibration *vib);
int scePadClose(int handle);

int sceUserServiceInitialize(void *);
int sceUserServiceGetLoginUserIdList(int user_ids[4]);
int sceUserServiceGetUserName(int user_id, char *name, size_t size);
int sceUserServiceGetForegroundUser(int *user_id);

int sceAudioOutInit(void);
int sceAudioOutOpen(int user_id, int type, int index, unsigned int len, unsigned int freq, unsigned int param);
int sceAudioOutOutput(int handle, const void *ptr);
int sceAudioOutClose(int handle);

typedef struct PS5_KeyboardState {
    uint64_t junk0[2];
    uint8_t available;
    uint32_t junk1[2];
    uint32_t modifiers;
    uint16_t scankey[16];
    uint64_t junk3[4];
} PS5_KeyboardState;

/* libSceKeyboard is not loaded for a native title: importing it leaves its functions
 * at address 0 (the 0.1.0-beta crash at start-up). It is loaded at run time instead,
 * like libSceMouse, and the keyboard is simply missing when that fails. */
typedef int (*PFN_sceKeyboardInit)(void);
typedef int (*PFN_sceKeyboardOpen)(int user_id, int type, int index, void *param);
typedef int (*PFN_sceKeyboardReadState)(int handle, PS5_KeyboardState *state);
static PFN_sceKeyboardReadState p_sceKeyboardReadState = NULL;

/* ps5/native/codename_ps5.c: a system library by name, and a function in it */
extern int cne_ps5_load_module(const char *name);
extern void *cne_ps5_module_symbol(int handle, const char *symbol);

#define PS5_PAD_BUTTON_L3        0x0002
#define PS5_PAD_BUTTON_R3        0x0004
#define PS5_PAD_BUTTON_OPTIONS   0x0008
#define PS5_PAD_BUTTON_UP        0x0010
#define PS5_PAD_BUTTON_RIGHT     0x0020
#define PS5_PAD_BUTTON_DOWN      0x0040
#define PS5_PAD_BUTTON_LEFT      0x0080
#define PS5_PAD_BUTTON_L2        0x0100
#define PS5_PAD_BUTTON_R2        0x0200
#define PS5_PAD_BUTTON_L1        0x0400
#define PS5_PAD_BUTTON_R1        0x0800
#define PS5_PAD_BUTTON_TRIANGLE  0x1000
#define PS5_PAD_BUTTON_CIRCLE    0x2000
#define PS5_PAD_BUTTON_CROSS     0x4000
#define PS5_PAD_BUTTON_SQUARE    0x8000
#define PS5_PAD_BUTTON_TOUCH_PAD 0x100000

#define PS5_TOUCHPAD_W 1920.0f
#define PS5_TOUCHPAD_H 1080.0f

/* ------------------------------------------------------------------------- */
/* Settings the game changes at run time (funkin.ps5.PS5Native)              */

static bool g_touchpad_mouse = true;
static float g_touchpad_speed = 1.0f;

void cne_ps5_set_touchpad_mouse(int enabled, double speed)
{
    g_touchpad_mouse = enabled != 0;
    g_touchpad_speed = speed > 0.05 ? (float)speed : 1.0f;
}

/* The display mode chosen at start-up, from display.cfg */
static int g_display_w = 1920, g_display_h = 1080, g_display_hz = 60, g_vsync = 0;

int cne_ps5_display_width(void) { return g_display_w; }
int cne_ps5_display_height(void) { return g_display_h; }
int cne_ps5_display_refresh(void) { return g_display_hz; }

static void read_display_config(void)
{
    FILE *f = fopen(CNE_PS5_DATA "display.cfg", "r");
    char line[128];
    int w = 1920, h = 1080, hz = 60, vsync = 0;
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            int v;
            if (sscanf(line, "width=%d", &v) == 1) w = v;
            else if (sscanf(line, "height=%d", &v) == 1) h = v;
            else if (sscanf(line, "refresh=%d", &v) == 1) hz = v;
            else if (sscanf(line, "vsync=%d", &v) == 1) vsync = v;
        }
        fclose(f);
    }
    if (!((w == 1920 && h == 1080) || (w == 2560 && h == 1440) || (w == 3840 && h == 2160))) {
        w = 1920;
        h = 1080;
    }
    g_display_w = w;
    g_display_h = h;
    g_display_hz = hz >= 120 ? 120 : 60;
    g_vsync = vsync ? 1 : 0;
}

/* ------------------------------------------------------------------------- */
/* Video: one OpenGL window through EGL                                     */

typedef struct PS5_VideoData {
    EGLDisplay display;
    EGLConfig config;
    EGLSurface surface;
    EGLContext context;
    SDL_Window *window;
    int interval;
} PS5_VideoData;

static PS5_VideoData *g_video = NULL;

static bool egl_error(const char *what)
{
    return SDL_SetError("ps5 %s: EGL error 0x%04x", what, eglGetError());
}

static void PS5_InitInput(void);
static void PS5_PumpInput(void);
extern void cne_ps5_hide_splash(void);

static bool PS5_VideoInit(SDL_VideoDevice *_this)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    SDL_DisplayMode mode;

    read_display_config();
    v->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (v->display == EGL_NO_DISPLAY) {
        return egl_error("eglGetDisplay");
    }
#ifdef CNE_PS5_DYNAMIC_DISPLAY
    if (!eglSetDisplayModePS5(v->display, g_display_w, g_display_h)) {
        g_display_w = 1920;
        g_display_h = 1080;
    }
    eglSetDisplayRefreshPS5(v->display, g_display_hz);
#else
    g_display_w = 1920;
    g_display_h = 1080;
    g_display_hz = 60;
#endif
    if (!eglInitialize(v->display, NULL, NULL)) {
        v->display = EGL_NO_DISPLAY;
        return egl_error("eglInitialize");
    }
    fprintf(stderr, "[codename-ps5] video: EGL up, %dx%d at %d Hz\n", g_display_w, g_display_h, g_display_hz);

    SDL_zero(mode);
    mode.format = SDL_PIXELFORMAT_ABGR8888;
    mode.w = g_display_w;
    mode.h = g_display_h;
    mode.refresh_rate = (float)g_display_hz;
    if (SDL_AddBasicVideoDisplay(&mode) == 0) {
        return false;
    }
    PS5_InitInput();
    cne_ps5_hide_splash(); /* the screen is ours now */
    return true;
}

static void PS5_VideoQuit(SDL_VideoDevice *_this)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    if (v->display == EGL_NO_DISPLAY) {
        return;
    }
    eglMakeCurrent(v->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (v->context) {
        eglDestroyContext(v->display, v->context);
        v->context = EGL_NO_CONTEXT;
    }
    if (v->surface) {
        eglDestroySurface(v->display, v->surface);
        v->surface = EGL_NO_SURFACE;
    }
    eglTerminate(v->display);
    v->display = EGL_NO_DISPLAY;
}

static bool PS5_CreateWindow(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID create_props)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    EGLint count = 0;
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, _this->gl_config.depth_size > 0 ? 24 : 0,
        EGL_STENCIL_SIZE, _this->gl_config.stencil_size > 0 ? 8 : 0,
        EGL_NONE
    };
    (void)create_props;

    if (v->window) {
        return SDL_SetError("ps5: only one window");
    }
    /* the console has one screen: the window always covers it */
    window->x = window->y = 0;
    window->w = window->windowed.w = window->floating.w = g_display_w;
    window->h = window->windowed.h = window->floating.h = g_display_h;
    window->flags |= SDL_WINDOW_FULLSCREEN | SDL_WINDOW_BORDERLESS | SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_MOUSE_FOCUS;
    window->flags &= ~SDL_WINDOW_RESIZABLE;

    if (window->flags & SDL_WINDOW_OPENGL) {
        if (!eglChooseConfig(v->display, attributes, &v->config, 1, &count) || count < 1) {
            return egl_error("eglChooseConfig");
        }
        v->surface = eglCreateWindowSurface(v->display, v->config, (EGLNativeWindowType)0, NULL);
        if (!v->surface) {
            return egl_error("eglCreateWindowSurface");
        }
    }
    v->window = window;
    v->interval = g_vsync;
    SDL_SetKeyboardFocus(window);
    SDL_SetMouseFocus(window);
    return true;
}

static void PS5_DestroyWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    if (v->window != window) {
        return;
    }
    v->window = NULL;
    eglMakeCurrent(v->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (v->surface) {
        eglDestroySurface(v->display, v->surface);
        v->surface = EGL_NO_SURFACE;
    }
}

static void PS5_SetWindowSize(SDL_VideoDevice *_this, SDL_Window *window)
{
    (void)_this;
    window->w = window->windowed.w = g_display_w;
    window->h = window->windowed.h = g_display_h;
}

static bool PS5_GL_LoadLibrary(SDL_VideoDevice *_this, const char *path)
{
    (void)_this;
    (void)path; /* statically linked */
    return true;
}

static SDL_FunctionPointer PS5_GL_GetProcAddress(SDL_VideoDevice *_this, const char *proc)
{
    (void)_this;
    return (SDL_FunctionPointer)eglGetProcAddress(proc);
}

static void PS5_GL_UnloadLibrary(SDL_VideoDevice *_this)
{
    (void)_this;
}

static bool PS5_GL_MakeCurrent(SDL_VideoDevice *_this, SDL_Window *window, SDL_GLContext context)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    EGLSurface surface = (context && window) ? v->surface : EGL_NO_SURFACE;
    if (!eglMakeCurrent(v->display, surface, surface, (EGLContext)context)) {
        return egl_error("eglMakeCurrent");
    }
    return true;
}

static SDL_GLContext PS5_GL_CreateContext(SDL_VideoDevice *_this, SDL_Window *window)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    int major = _this->gl_config.major_version, minor = _this->gl_config.minor_version;
    const bool core = _this->gl_config.profile_mask == SDL_GL_CONTEXT_PROFILE_CORE;
    EGLint attributes[8];
    int n = 0;

    /* Lime asks for whatever its renderer needs; OpenFL's renderer is written for
       compatibility-profile GL, which ps5-opengl offers up to 4.6. */
    if (major < 2) {
        major = 2;
        minor = 1;
    }
    if (core && (major * 10 + minor) < 33) {
        major = 3;
        minor = 3;
    }
    attributes[n++] = EGL_CONTEXT_MAJOR_VERSION_KHR;
    attributes[n++] = major;
    attributes[n++] = EGL_CONTEXT_MINOR_VERSION_KHR;
    attributes[n++] = minor;
    attributes[n++] = EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR;
    attributes[n++] = core ? EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR : EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR;
    attributes[n++] = EGL_NONE;

    if (v->context) {
        SDL_SetError("ps5: one OpenGL context only");
        return NULL;
    }
    if (!eglBindAPI(EGL_OPENGL_API)) {
        egl_error("eglBindAPI");
        return NULL;
    }
    v->context = eglCreateContext(v->display, v->config, EGL_NO_CONTEXT, attributes);
    if (!v->context) {
        /* an older SDK without the asked-for version: take its default */
        const EGLint fallback[] = { EGL_NONE };
        v->context = eglCreateContext(v->display, v->config, EGL_NO_CONTEXT, fallback);
        if (!v->context) {
            egl_error("eglCreateContext");
            return NULL;
        }
    }
    if (!PS5_GL_MakeCurrent(_this, window, (SDL_GLContext)v->context)) {
        eglDestroyContext(v->display, v->context);
        v->context = EGL_NO_CONTEXT;
        return NULL;
    }
    eglSwapInterval(v->display, v->interval);
    return (SDL_GLContext)v->context;
}

static bool PS5_GL_SetSwapInterval(SDL_VideoDevice *_this, int interval)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    if (interval < 0) {
        interval = 1; /* no adaptive sync: plain V-Sync */
    }
    if (interval > 1) {
        interval = 1;
    }
    if (!eglSwapInterval(v->display, interval)) {
        return egl_error("eglSwapInterval");
    }
    v->interval = interval;
    return true;
}

static bool PS5_GL_GetSwapInterval(SDL_VideoDevice *_this, int *interval)
{
    *interval = ((PS5_VideoData *)_this->internal)->interval;
    return true;
}

static bool PS5_GL_SwapWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    (void)window;
    return eglSwapBuffers(v->display, v->surface) ? true : egl_error("eglSwapBuffers");
}

static bool PS5_GL_DestroyContext(SDL_VideoDevice *_this, SDL_GLContext context)
{
    PS5_VideoData *v = (PS5_VideoData *)_this->internal;
    if (!context || (EGLContext)context != v->context) {
        return true;
    }
    eglMakeCurrent(v->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(v->display, v->context);
    v->context = EGL_NO_CONTEXT;
    return true;
}

static void PS5_PumpEvents(SDL_VideoDevice *_this)
{
    (void)_this;
    PS5_PumpInput();
}

static bool PS5_StartTextInput(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID props)
{
    (void)_this; (void)window; (void)props;
    return true; /* typed text comes from the USB keyboard in PS5_PumpInput */
}

static bool PS5_StopTextInput(SDL_VideoDevice *_this, SDL_Window *window)
{
    (void)_this; (void)window;
    return true;
}

static void PS5_DeleteDevice(SDL_VideoDevice *device)
{
    SDL_free(device->internal);
    SDL_free(device);
    g_video = NULL;
}

static SDL_VideoDevice *PS5_CreateDevice(void)
{
    SDL_VideoDevice *device = (SDL_VideoDevice *)SDL_calloc(1, sizeof(SDL_VideoDevice));
    if (!device) {
        return NULL;
    }
    g_video = (PS5_VideoData *)SDL_calloc(1, sizeof(PS5_VideoData));
    if (!g_video) {
        SDL_free(device);
        return NULL;
    }
    device->internal = (SDL_VideoData *)g_video;
    device->VideoInit = PS5_VideoInit;
    device->VideoQuit = PS5_VideoQuit;
    device->CreateSDLWindow = PS5_CreateWindow;
    device->DestroyWindow = PS5_DestroyWindow;
    device->SetWindowSize = PS5_SetWindowSize;
    device->PumpEvents = PS5_PumpEvents;
    device->StartTextInput = PS5_StartTextInput;
    device->StopTextInput = PS5_StopTextInput;
    device->GL_LoadLibrary = PS5_GL_LoadLibrary;
    device->GL_GetProcAddress = PS5_GL_GetProcAddress;
    device->GL_UnloadLibrary = PS5_GL_UnloadLibrary;
    device->GL_CreateContext = PS5_GL_CreateContext;
    device->GL_MakeCurrent = PS5_GL_MakeCurrent;
    device->GL_SetSwapInterval = PS5_GL_SetSwapInterval;
    device->GL_GetSwapInterval = PS5_GL_GetSwapInterval;
    device->GL_SwapWindow = PS5_GL_SwapWindow;
    device->GL_DestroyContext = PS5_GL_DestroyContext;
    device->free = PS5_DeleteDevice;
    device->device_caps = VIDEO_DEVICE_CAPS_FULLSCREEN_ONLY;
    return device;
}

VideoBootStrap PRIVATE_bootstrap = { "ps5", "PlayStation 5 (ps5-opengl EGL)", PS5_CreateDevice, NULL, true };

/* ------------------------------------------------------------------------- */
/* Keyboard, mouse and the touchpad pointer                                   */

#define PS5_KEYBOARD_ID ((SDL_KeyboardID)0x5005)
#define PS5_MOUSE_ID ((SDL_MouseID)0x5005)
#define PS5_TOUCH_MOUSE_ID ((SDL_MouseID)0x5006)

static int g_keyboard = -1;
static PS5_KeyboardState g_prev_keys;

typedef struct PS5_MouseData {
    uint64_t timestamp;
    bool connected;
    uint32_t buttons;
    int32_t x;
    int32_t y;
    int32_t wheel;
    int32_t tilt;
    uint8_t reserve[8];
} PS5_MouseData;

typedef int (*PFN_sceMouseInit)(void);
typedef int (*PFN_sceMouseOpen)(int user_id, int type, int index, void *param);
typedef int (*PFN_sceMouseRead)(int handle, PS5_MouseData *data, int num);
static PFN_sceMouseRead p_sceMouseRead = NULL;
static int g_mouse = -1;
static uint32_t g_mouse_buttons = 0;

static float g_pointer_x = 960.0f, g_pointer_y = 540.0f;

static int foreground_user(void)
{
    int user = -1;
    if (sceUserServiceGetForegroundUser(&user) != 0 || user < 0) {
        int users[4] = { -1, -1, -1, -1 };
        if (sceUserServiceGetLoginUserIdList(users) == 0) {
            for (int i = 0; i < 4; i++) {
                if (users[i] != -1) {
                    return users[i];
                }
            }
        }
    }
    return user;
}

static void PS5_InitInput(void)
{
    int user;
    sceUserServiceInitialize(0);
    user = foreground_user();

    SDL_AddKeyboard(PS5_KEYBOARD_ID, "USB keyboard");
    SDL_AddMouse(PS5_MOUSE_ID, "USB mouse");
    SDL_AddMouse(PS5_TOUCH_MOUSE_ID, "DualSense touchpad");
    g_pointer_x = g_display_w / 2.0f;
    g_pointer_y = g_display_h / 2.0f;

    {
        int module = cne_ps5_load_module("libSceKeyboard");
        PFN_sceKeyboardInit p_init = (PFN_sceKeyboardInit)cne_ps5_module_symbol(module, "sceKeyboardInit");
        PFN_sceKeyboardOpen p_open = (PFN_sceKeyboardOpen)cne_ps5_module_symbol(module, "sceKeyboardOpen");
        p_sceKeyboardReadState = (PFN_sceKeyboardReadState)cne_ps5_module_symbol(module, "sceKeyboardReadState");
        if (p_init && p_open && p_sceKeyboardReadState) {
            char junk[16] = { 0 };
            p_init(); /* already initialised by the system on some firmware: ignore */
            g_keyboard = p_open(user, 0, 0, junk);
            if (g_keyboard < 0) {
                g_keyboard = -1;
            }
        }
        fprintf(stderr, "[codename-ps5] keyboard: module %d, handle %d\n", module, g_keyboard);
    }
    SDL_zero(g_prev_keys);

    /* libSceMouse is not part of every firmware's game libraries: load it if it is there */
    {
        int module = cne_ps5_load_module("libSceMouse");
        if (module >= 0) {
            PFN_sceMouseInit p_init = (PFN_sceMouseInit)cne_ps5_module_symbol(module, "sceMouseInit");
            PFN_sceMouseOpen p_open = (PFN_sceMouseOpen)cne_ps5_module_symbol(module, "sceMouseOpen");
            p_sceMouseRead = (PFN_sceMouseRead)cne_ps5_module_symbol(module, "sceMouseRead");
            if (p_init && p_open && p_sceMouseRead) {
                char param[8] = { 0 };
                p_init();
                g_mouse = p_open(user, 0, 0, param);
                if (g_mouse < 0) {
                    g_mouse = -1;
                }
            }
        }
    }
}

static void send_key(Uint64 ts, SDL_Scancode code, bool down)
{
    SDL_SendKeyboardKey(ts, PS5_KEYBOARD_ID, (int)code, code, down);
    if (down && SDL_TextInputActive(SDL_GetKeyboardFocus())) {
        SDL_Keycode key = SDL_GetKeyFromScancode(code, SDL_GetModState(), false);
        if (key >= 0x20 && key < 0x7F) {
            char text[2] = { (char)key, 0 };
            SDL_SendKeyboardText(text);
        }
    }
}

static void pump_keyboard(Uint64 ts)
{
    static const SDL_Scancode modifier_codes[8] = {
        SDL_SCANCODE_LCTRL, SDL_SCANCODE_LSHIFT, SDL_SCANCODE_LALT, SDL_SCANCODE_LGUI,
        SDL_SCANCODE_RCTRL, SDL_SCANCODE_RSHIFT, SDL_SCANCODE_RALT, SDL_SCANCODE_RGUI
    };
    PS5_KeyboardState cur;
    uint32_t diff;

    if (g_keyboard < 0 || !p_sceKeyboardReadState || p_sceKeyboardReadState(g_keyboard, &cur) != 0 || !cur.available) {
        return;
    }
    diff = g_prev_keys.modifiers ^ cur.modifiers;
    for (int i = 0; i < 8; i++) {
        if (diff & (1u << i)) {
            SDL_SendKeyboardKey(ts, PS5_KEYBOARD_ID, (int)modifier_codes[i], modifier_codes[i], (cur.modifiers & (1u << i)) != 0);
        }
    }
    /* keys released: in the old list, not in the new one */
    for (int i = 0; i < 16; i++) {
        uint16_t k = g_prev_keys.scankey[i];
        bool still = false;
        if (!k) continue;
        for (int j = 0; j < 16; j++) still |= cur.scankey[j] == k;
        if (!still && k < SDL_SCANCODE_COUNT) send_key(ts, (SDL_Scancode)k, false);
    }
    for (int i = 0; i < 16; i++) {
        uint16_t k = cur.scankey[i];
        bool was = false;
        if (!k) continue;
        for (int j = 0; j < 16; j++) was |= g_prev_keys.scankey[j] == k;
        if (!was && k < SDL_SCANCODE_COUNT) send_key(ts, (SDL_Scancode)k, true);
    }
    SDL_memcpy(&g_prev_keys, &cur, sizeof(cur));
}

static void pump_mouse(Uint64 ts)
{
    PS5_MouseData data[8];
    SDL_Window *window = SDL_GetMouseFocus();
    int n;
    if (g_mouse < 0 || !p_sceMouseRead || !window) {
        return;
    }
    n = p_sceMouseRead(g_mouse, data, 8);
    for (int i = 0; i < n; i++) {
        uint32_t changed;
        if (!data[i].connected) continue;
        if (data[i].x || data[i].y) {
            g_pointer_x = SDL_clamp(g_pointer_x + data[i].x, 0.0f, (float)(g_display_w - 1));
            g_pointer_y = SDL_clamp(g_pointer_y + data[i].y, 0.0f, (float)(g_display_h - 1));
            SDL_SendMouseMotion(ts, window, PS5_MOUSE_ID, false, g_pointer_x, g_pointer_y);
        }
        if (data[i].wheel) {
            SDL_SendMouseWheel(ts, window, PS5_MOUSE_ID, 0.0f, (float)data[i].wheel, SDL_MOUSEWHEEL_NORMAL);
        }
        changed = g_mouse_buttons ^ data[i].buttons;
        if (changed & 0x1) SDL_SendMouseButton(ts, window, PS5_MOUSE_ID, SDL_BUTTON_LEFT, (data[i].buttons & 0x1) != 0);
        if (changed & 0x2) SDL_SendMouseButton(ts, window, PS5_MOUSE_ID, SDL_BUTTON_RIGHT, (data[i].buttons & 0x2) != 0);
        if (changed & 0x4) SDL_SendMouseButton(ts, window, PS5_MOUSE_ID, SDL_BUTTON_MIDDLE, (data[i].buttons & 0x4) != 0);
        g_mouse_buttons = data[i].buttons;
    }
}

static void PS5_PumpInput(void)
{
    Uint64 ts = SDL_GetTicksNS();
    pump_keyboard(ts);
    pump_mouse(ts);
}

/*
 * The touchpad as a laptop trackpad: a finger sliding moves the pointer from where
 * it is, a click is the left button and a click with two fingers down the right one.
 */
static struct {
    bool tracking;
    uint8_t finger;
    float last_x, last_y;
    bool clicked;
    uint8_t click_button;
} g_tp;

static void touchpad_pointer(Uint64 ts, const PS5_PadData *pad, bool clicked)
{
    SDL_Window *window = SDL_GetMouseFocus();
    if (!g_touchpad_mouse || !window) {
        g_tp.tracking = false;
        return;
    }
    if (pad->touch.fingers > 0) {
        const PS5_PadTouch *t = &pad->touch.touch[0];
        float x = (float)t->x, y = (float)t->y;
        if (g_tp.tracking && g_tp.finger == t->finger) {
            /* a full swipe across the pad crosses about 3/4 of the screen at speed 1 */
            float scale = g_touchpad_speed * 0.75f * (float)g_display_w / PS5_TOUCHPAD_W;
            float dx = (x - g_tp.last_x) * scale, dy = (y - g_tp.last_y) * scale;
            if (dx != 0.0f || dy != 0.0f) {
                g_pointer_x = SDL_clamp(g_pointer_x + dx, 0.0f, (float)(g_display_w - 1));
                g_pointer_y = SDL_clamp(g_pointer_y + dy, 0.0f, (float)(g_display_h - 1));
                SDL_SendMouseMotion(ts, window, PS5_TOUCH_MOUSE_ID, false, g_pointer_x, g_pointer_y);
            }
        }
        g_tp.tracking = true;
        g_tp.finger = t->finger;
        g_tp.last_x = x;
        g_tp.last_y = y;
    } else {
        g_tp.tracking = false;
    }
    if (clicked != g_tp.clicked) {
        if (clicked) {
            g_tp.click_button = pad->touch.fingers >= 2 ? SDL_BUTTON_RIGHT : SDL_BUTTON_LEFT;
        }
        SDL_SendMouseButton(ts, window, PS5_TOUCH_MOUSE_ID, g_tp.click_button, clicked);
        g_tp.clicked = clicked;
    }
}

/* ------------------------------------------------------------------------- */
/* Joystick: DualSense controllers                                            */

#define PS5_MAX_USERS 4
#define PS5_AXIS_LX 0
#define PS5_AXIS_LY 1
#define PS5_AXIS_RX 2
#define PS5_AXIS_RY 3
#define PS5_AXIS_L2 4
#define PS5_AXIS_R2 5

typedef struct PS5_Pad {
    int user_id;
    char name[64];
    int handle;
    SDL_JoystickID instance_id;
    PS5_PadData last;
    bool touch_down[2];
} PS5_Pad;

static PS5_Pad g_pads[PS5_MAX_USERS];

/* button order = gamepad mapping below */
static const uint32_t g_btn_map[] = {
    PS5_PAD_BUTTON_CROSS,     /* 0  a */
    PS5_PAD_BUTTON_CIRCLE,    /* 1  b */
    PS5_PAD_BUTTON_SQUARE,    /* 2  x */
    PS5_PAD_BUTTON_TRIANGLE,  /* 3  y */
    PS5_PAD_BUTTON_TOUCH_PAD, /* 4  touchpad */
    PS5_PAD_BUTTON_OPTIONS,   /* 5  start */
    PS5_PAD_BUTTON_L3,        /* 6  leftstick */
    PS5_PAD_BUTTON_R3,        /* 7  rightstick */
    PS5_PAD_BUTTON_L1,        /* 8  leftshoulder */
    PS5_PAD_BUTTON_R1,        /* 9  rightshoulder */
    PS5_PAD_BUTTON_UP,        /* 10 dpup */
    PS5_PAD_BUTTON_DOWN,      /* 11 dpdown */
    PS5_PAD_BUTTON_LEFT,      /* 12 dpleft */
    PS5_PAD_BUTTON_RIGHT,     /* 13 dpright */
};

static Sint16 axis(uint8_t v)
{
    int centered = (int)v - 128;
    if (centered > -6 && centered < 6) {
        return 0;
    }
    return (Sint16)SDL_clamp(centered * 258, -32768, 32767);
}

static Sint16 trigger(uint8_t v)
{
    return (Sint16)(((int)v * 65535) / 255 - 32768);
}

static PS5_Pad *pad_by_index(int device_index)
{
    int n = 0;
    for (int i = 0; i < PS5_MAX_USERS; i++) {
        if (g_pads[i].instance_id == 0) continue;
        if (n++ == device_index) return &g_pads[i];
    }
    return NULL;
}

static PS5_Pad *pad_by_joystick(SDL_Joystick *joystick)
{
    for (int i = 0; i < PS5_MAX_USERS; i++) {
        if (g_pads[i].instance_id != 0 && g_pads[i].instance_id == joystick->instance_id) return &g_pads[i];
    }
    return NULL;
}

static void PS5_JoystickDetect(void)
{
    int users[PS5_MAX_USERS] = { -1, -1, -1, -1 };
    if (sceUserServiceGetLoginUserIdList(users) != 0) {
        return;
    }
    for (int i = 0; i < PS5_MAX_USERS; i++) {
        PS5_Pad *p = &g_pads[i];
        if (users[i] == p->user_id) continue;
        if (p->instance_id != 0) {
            SDL_PrivateJoystickRemoved(p->instance_id);
            if (p->handle >= 0) scePadClose(p->handle);
            p->instance_id = 0;
            p->handle = -1;
        }
        p->user_id = users[i];
        if (users[i] != -1) {
            if (sceUserServiceGetUserName(users[i], p->name, sizeof(p->name)) != 0 || !p->name[0]) {
                SDL_snprintf(p->name, sizeof(p->name), "DualSense %d", i + 1);
            }
            p->instance_id = SDL_GetNextObjectID();
            SDL_zero(p->last);
            SDL_PrivateJoystickAdded(p->instance_id);
        }
    }
}

static bool PS5_JoystickInit(void)
{
    for (int i = 0; i < PS5_MAX_USERS; i++) {
        g_pads[i].user_id = -1;
        g_pads[i].handle = -1;
        g_pads[i].instance_id = 0;
    }
    sceUserServiceInitialize(0);
    if (scePadInit() != 0) {
        return SDL_SetError("scePadInit failed");
    }
    PS5_JoystickDetect();
    return true;
}

static int PS5_JoystickGetCount(void)
{
    int n = 0;
    for (int i = 0; i < PS5_MAX_USERS; i++) n += g_pads[i].instance_id != 0;
    return n;
}

static bool PS5_JoystickIsDevicePresent(Uint16 vendor_id, Uint16 product_id, Uint16 version, const char *name)
{
    return false;
}

static const char *PS5_JoystickGetDeviceName(int device_index)
{
    PS5_Pad *p = pad_by_index(device_index);
    return p ? "PS5 DualSense Wireless Controller" : NULL;
}

static const char *PS5_JoystickGetDevicePath(int device_index) { return NULL; }
static int PS5_JoystickGetDeviceSteamVirtualGamepadSlot(int device_index) { return -1; }

static int PS5_JoystickGetDevicePlayerIndex(int device_index)
{
    PS5_Pad *p = pad_by_index(device_index);
    return p ? (int)(p - g_pads) : -1;
}

static void PS5_JoystickSetDevicePlayerIndex(int device_index, int player_index) {}

static SDL_GUID PS5_JoystickGetDeviceGUID(int device_index)
{
    /* Sony, DualSense: the same IDs the PC uses, so mappings and names line up */
    return SDL_CreateJoystickGUID(SDL_HARDWARE_BUS_BLUETOOTH, 0x054c, 0x0ce6, 0x0100, "Sony", "PS5 DualSense Wireless Controller", 0, 0);
}

static SDL_JoystickID PS5_JoystickGetDeviceInstanceID(int device_index)
{
    PS5_Pad *p = pad_by_index(device_index);
    return p ? p->instance_id : 0;
}

static bool PS5_JoystickOpen(SDL_Joystick *joystick, int device_index)
{
    PS5_Pad *p = pad_by_index(device_index);
    if (!p) {
        return SDL_SetError("ps5: no controller %d", device_index);
    }
    if (p->handle < 0) {
        p->handle = scePadOpen(p->user_id, 0, 0, NULL);
        if (p->handle < 0) {
            return SDL_SetError("scePadOpen: 0x%08x", p->handle);
        }
    }
    scePadSetVibrationMode(p->handle, 2);
    joystick->nbuttons = SDL_arraysize(g_btn_map);
    joystick->naxes = 6;
    joystick->nhats = 1;
    SDL_PrivateJoystickAddTouchpad(joystick, 2);
    return true;
}

static bool PS5_JoystickRumble(SDL_Joystick *joystick, Uint16 low, Uint16 high)
{
    PS5_Pad *p = pad_by_joystick(joystick);
    PS5_PadVibration vib = { (uint8_t)(low >> 8), (uint8_t)(high >> 8) };
    if (!p || p->handle < 0) return SDL_Unsupported();
    return scePadSetVibration(p->handle, &vib) == 0;
}

static bool PS5_JoystickRumbleTriggers(SDL_Joystick *joystick, Uint16 left, Uint16 right) { return SDL_Unsupported(); }

static bool PS5_JoystickSetLED(SDL_Joystick *joystick, Uint8 red, Uint8 green, Uint8 blue)
{
    PS5_Pad *p = pad_by_joystick(joystick);
    PS5_PadColor c = { red, green, blue, 255 };
    if (!p || p->handle < 0) return SDL_Unsupported();
    return scePadSetLightBar(p->handle, &c) == 0;
}

static bool PS5_JoystickSendEffect(SDL_Joystick *joystick, const void *data, int size) { return SDL_Unsupported(); }
static bool PS5_JoystickSetSensorsEnabled(SDL_Joystick *joystick, bool enabled) { return SDL_Unsupported(); }

static void PS5_JoystickUpdate(SDL_Joystick *joystick)
{
    PS5_Pad *p = pad_by_joystick(joystick);
    PS5_PadData pad;
    Uint64 ts = SDL_GetTicksNS();
    uint32_t changed;

    if (!p || p->handle < 0) return;
    SDL_zero(pad);
    if (scePadReadState(p->handle, &pad) != 0) return;

    if (pad.leftStick.x != p->last.leftStick.x) SDL_SendJoystickAxis(ts, joystick, PS5_AXIS_LX, axis(pad.leftStick.x));
    if (pad.leftStick.y != p->last.leftStick.y) SDL_SendJoystickAxis(ts, joystick, PS5_AXIS_LY, axis(pad.leftStick.y));
    if (pad.rightStick.x != p->last.rightStick.x) SDL_SendJoystickAxis(ts, joystick, PS5_AXIS_RX, axis(pad.rightStick.x));
    if (pad.rightStick.y != p->last.rightStick.y) SDL_SendJoystickAxis(ts, joystick, PS5_AXIS_RY, axis(pad.rightStick.y));
    if (pad.analogButtons.l2 != p->last.analogButtons.l2) SDL_SendJoystickAxis(ts, joystick, PS5_AXIS_L2, trigger(pad.analogButtons.l2));
    if (pad.analogButtons.r2 != p->last.analogButtons.r2) SDL_SendJoystickAxis(ts, joystick, PS5_AXIS_R2, trigger(pad.analogButtons.r2));

    changed = pad.buttons ^ p->last.buttons;
    if (changed) {
        Uint8 hat = SDL_HAT_CENTERED;
        for (int i = 0; i < (int)SDL_arraysize(g_btn_map); i++) {
            if (changed & g_btn_map[i]) SDL_SendJoystickButton(ts, joystick, (Uint8)i, (pad.buttons & g_btn_map[i]) != 0);
        }
        if (pad.buttons & PS5_PAD_BUTTON_UP) hat |= SDL_HAT_UP;
        if (pad.buttons & PS5_PAD_BUTTON_DOWN) hat |= SDL_HAT_DOWN;
        if (pad.buttons & PS5_PAD_BUTTON_LEFT) hat |= SDL_HAT_LEFT;
        if (pad.buttons & PS5_PAD_BUTTON_RIGHT) hat |= SDL_HAT_RIGHT;
        SDL_SendJoystickHat(ts, joystick, 0, hat);
    }

    /* the touchpad, as SDL touchpad events and as the pointer */
    for (int f = 0; f < 2; f++) {
        bool down = f < pad.touch.fingers;
        if (down || p->touch_down[f]) {
            const PS5_PadTouch *t = &pad.touch.touch[f];
            SDL_SendJoystickTouchpad(ts, joystick, 0, f, down, t->x / PS5_TOUCHPAD_W, t->y / PS5_TOUCHPAD_H, down ? 1.0f : 0.0f);
        }
        p->touch_down[f] = down;
    }
    if (p == &g_pads[0] || p->user_id == foreground_user()) {
        touchpad_pointer(ts, &pad, (pad.buttons & PS5_PAD_BUTTON_TOUCH_PAD) != 0);
    }

    SDL_memcpy(&p->last, &pad, sizeof(pad));
}

static void PS5_JoystickClose(SDL_Joystick *joystick)
{
    PS5_Pad *p = pad_by_joystick(joystick);
    if (p && p->handle >= 0) {
        scePadClose(p->handle);
        p->handle = -1;
    }
}

static void PS5_JoystickQuit(void) {}

static bool PS5_JoystickGetGamepadMapping(int device_index, SDL_GamepadMapping *out)
{
    if (!pad_by_index(device_index)) return false;
    SDL_zerop(out);
#define B(field, n) out->field.kind = EMappingKind_Button; out->field.target = n;
#define A(field, n) out->field.kind = EMappingKind_Axis; out->field.target = n;
    B(a, 0) B(b, 1) B(x, 2) B(y, 3) B(touchpad, 4) B(start, 5) B(leftstick, 6) B(rightstick, 7)
    B(leftshoulder, 8) B(rightshoulder, 9) B(dpup, 10) B(dpdown, 11) B(dpleft, 12) B(dpright, 13)
    A(leftx, PS5_AXIS_LX) A(lefty, PS5_AXIS_LY) A(rightx, PS5_AXIS_RX) A(righty, PS5_AXIS_RY)
    A(lefttrigger, PS5_AXIS_L2) A(righttrigger, PS5_AXIS_R2)
#undef B
#undef A
    return true;
}

SDL_JoystickDriver SDL_PRIVATE_JoystickDriver = {
    PS5_JoystickInit,
    PS5_JoystickGetCount,
    PS5_JoystickDetect,
    PS5_JoystickIsDevicePresent,
    PS5_JoystickGetDeviceName,
    PS5_JoystickGetDevicePath,
    PS5_JoystickGetDeviceSteamVirtualGamepadSlot,
    PS5_JoystickGetDevicePlayerIndex,
    PS5_JoystickSetDevicePlayerIndex,
    PS5_JoystickGetDeviceGUID,
    PS5_JoystickGetDeviceInstanceID,
    PS5_JoystickOpen,
    PS5_JoystickRumble,
    PS5_JoystickRumbleTriggers,
    PS5_JoystickSetLED,
    PS5_JoystickSendEffect,
    PS5_JoystickSetSensorsEnabled,
    PS5_JoystickUpdate,
    PS5_JoystickClose,
    PS5_JoystickQuit,
    PS5_JoystickGetGamepadMapping
};

/* ------------------------------------------------------------------------- */
/* Audio: libSceAudioOut, 48 kHz                                              */

#define PS5_AUDIO_PORT_MAIN 0
#define PS5_AUDIO_S16_STEREO 1
#define PS5_AUDIO_FLOAT_STEREO 4
#define PS5_USER_SYSTEM 0xFF

struct SDL_PrivateAudioData {
    int handle;
    Uint8 *buffer;
};

static bool PS5AUDIO_OpenDevice(SDL_AudioDevice *device)
{
    unsigned int fmt;
    device->hidden = (struct SDL_PrivateAudioData *)SDL_calloc(1, sizeof(*device->hidden));
    if (!device->hidden) return false;

    device->spec.freq = 48000;
    device->spec.channels = 2;
    if (device->spec.format == SDL_AUDIO_F32) {
        fmt = PS5_AUDIO_FLOAT_STEREO;
    } else {
        device->spec.format = SDL_AUDIO_S16;
        fmt = PS5_AUDIO_S16_STEREO;
    }
    /* the system takes 256 to 2048 frames a call, in steps of 256 */
    device->sample_frames = SDL_clamp(((device->sample_frames + 255) / 256) * 256, 256, 2048);
    SDL_UpdatedAudioDeviceFormat(device);

    device->hidden->handle = sceAudioOutOpen(PS5_USER_SYSTEM, PS5_AUDIO_PORT_MAIN, 0,
                                             (unsigned int)device->sample_frames, 48000, fmt);
    if (device->hidden->handle < 0) {
        return SDL_SetError("sceAudioOutOpen: 0x%08x", device->hidden->handle);
    }
    device->hidden->buffer = (Uint8 *)SDL_aligned_alloc(64, device->buffer_size);
    if (!device->hidden->buffer) return false;
    SDL_memset(device->hidden->buffer, 0, device->buffer_size);
    return true;
}

static bool PS5AUDIO_WaitDevice(SDL_AudioDevice *device)
{
    return true; /* sceAudioOutOutput blocks until the system takes the buffer */
}

static bool PS5AUDIO_PlayDevice(SDL_AudioDevice *device, const Uint8 *buffer, int buflen)
{
    return sceAudioOutOutput(device->hidden->handle, buffer) >= 0;
}

static Uint8 *PS5AUDIO_GetDeviceBuf(SDL_AudioDevice *device, int *buffer_size)
{
    return device->hidden->buffer;
}

static void PS5AUDIO_CloseDevice(SDL_AudioDevice *device)
{
    if (!device->hidden) return;
    if (device->hidden->handle >= 0) {
        sceAudioOutOutput(device->hidden->handle, NULL); /* drain */
        sceAudioOutClose(device->hidden->handle);
    }
    SDL_aligned_free(device->hidden->buffer);
    SDL_free(device->hidden);
    device->hidden = NULL;
}

static bool PS5AUDIO_Init(SDL_AudioDriverImpl *impl)
{
    static bool initialized = false;
    if (!initialized) {
        int rc = sceAudioOutInit();
        if (rc != 0 && rc != (int)0x8026000E /* already initialised */) {
            return false;
        }
        initialized = true;
    }
    impl->OpenDevice = PS5AUDIO_OpenDevice;
    impl->WaitDevice = PS5AUDIO_WaitDevice;
    impl->PlayDevice = PS5AUDIO_PlayDevice;
    impl->GetDeviceBuf = PS5AUDIO_GetDeviceBuf;
    impl->CloseDevice = PS5AUDIO_CloseDevice;
    impl->OnlyHasDefaultPlaybackDevice = true;
    return true;
}

AudioBootStrap PRIVATEAUDIO_bootstrap = { "ps5", "PlayStation 5 audio out", PS5AUDIO_Init, false, true };

/* ------------------------------------------------------------------------- */
/* Files                                                                      */

char *SDL_SYS_GetBasePath(void)
{
    return SDL_strdup("/app0/");
}

char *SDL_SYS_GetPrefPath(const char *org, const char *app)
{
    char path[512];
    const char *parts[] = { CNE_PS5_DATA, CNE_PS5_DATA "saves/", NULL, NULL };
    SDL_snprintf(path, sizeof(path), CNE_PS5_DATA "saves/%s/%s/", org && *org ? org : "app", app && *app ? app : "app");
    mkdir(parts[0], 0777);
    mkdir(parts[1], 0777);
    {
        /* make each level */
        char partial[512];
        for (size_t i = 1; path[i]; i++) {
            if (path[i] == '/') {
                SDL_memcpy(partial, path, i);
                partial[i] = 0;
                mkdir(partial, 0777);
            }
        }
    }
    return SDL_strdup(path);
}

char *SDL_SYS_GetUserFolder(SDL_Folder folder)
{
    (void)folder;
    return SDL_strdup(CNE_PS5_DATA);
}
