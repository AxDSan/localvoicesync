#include "hotkey_wrapper.h"
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <stdio.h>

bool x11_is_key_pressed(uint32_t key_code) {
    Display *d = XOpenDisplay(NULL);
    if (!d) return false;

    char keys[32];
    XQueryKeymap(d, keys);
    XCloseDisplay(d);

    return (keys[key_code / 8] & (1 << (key_code % 8))) != 0;
}

uint32_t x11_get_keycode(const char* keysym_name) {
    Display *d = XOpenDisplay(NULL);
    if (!d) return 0;

    KeySym sym = XStringToKeysym(keysym_name);
    if (sym == NoSymbol) {
        XCloseDisplay(d);
        return 0;
    }

    KeyCode code = XKeysymToKeycode(d, sym);
    XCloseDisplay(d);
    return (uint32_t)code;
}

uint32_t x11_get_pressed_keycode() {
    Display *d = XOpenDisplay(NULL);
    if (!d) return 0;

    char keys[32];
    XQueryKeymap(d, keys);
    XCloseDisplay(d);

    for (int i = 0; i < 256; i++) {
        if (keys[i / 8] & (1 << (i % 8))) {
            return (uint32_t)i;
        }
    }

    return 0;
}

const char* x11_get_keysym_name(uint32_t key_code) {
    Display *d = XOpenDisplay(NULL);
    if (!d) return NULL;

    KeySym sym = XKeycodeToKeysym(d, (KeyCode)key_code, 0);
    if (sym == NoSymbol) {
        XCloseDisplay(d);
        return NULL;
    }

    const char* name = XKeysymToString(sym);
    XCloseDisplay(d);
    return name;
}
