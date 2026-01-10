#ifndef HOTKEY_WRAPPER_H
#define HOTKEY_WRAPPER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns true if the key is pressed on X11.
// key_code is the X11 KeyCode.
bool x11_is_key_pressed(uint32_t key_code);

// Returns the X11 KeyCode for a given KeySym string (e.g., "F12").
uint32_t x11_get_keycode(const char* keysym_name);

// Returns the KeyCode of the first pressed key found, or 0 if none.
uint32_t x11_get_pressed_keycode();

// Returns the name of the keysym for a given keycode.
const char* x11_get_keysym_name(uint32_t key_code);

#ifdef __cplusplus
}
#endif

#endif // HOTKEY_WRAPPER_H
