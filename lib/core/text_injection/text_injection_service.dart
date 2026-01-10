import 'dart:io';
import 'package:flutter/services.dart';

class TextInjectionService {
  bool _isWayland = Platform.environment['XDG_SESSION_TYPE'] == 'wayland';

  Future<void> injectText(String text, {String method = 'dotool'}) async {
    if (method == 'Clipboard') {
      await _injectClipboard(text);
      return;
    }

    if (_isWayland) {
      await _injectWayland(text);
    } else {
      await _injectX11(text);
    }
  }

  Future<void> _injectClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    // Optional: simulate Ctrl+V if we want it to actually paste
    if (_isWayland) {
      try {
        await Process.run('ydotool', ['key', '29:1', '47:1', '47:0', '29:0']); // Ctrl+V
      } catch (_) {}
    } else {
      try {
        await Process.run('xdotool', ['key', 'ctrl+v']);
      } catch (_) {}
    }
  }

  Future<void> _injectX11(String text) async {
    try {
      await Process.run('xdotool', ['type', '--clearmodifiers', text]);
    } catch (e) {
      print('X11 Injection Error: $e');
    }
  }

  Future<void> _injectWayland(String text) async {
    try {
      // Use ydotool with a small delay between characters if needed
      // but 'type' should work. 
      // Ensure YDOTOOL_SOCKET is handled if user has it in a non-standard place.
      final result = await Process.run('ydotool', ['type', text]);
      if (result.exitCode != 0) {
        // Fallback to wtype
        await Process.run('wtype', [text]);
      }
    } catch (e) {
      try {
        await Process.run('wtype', [text]);
      } catch (e2) {
        print('Wayland Injection Error: $e2');
      }
    }
  }
}
