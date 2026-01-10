import 'dart:io';
import 'package:flutter/services.dart';

class TextInjectionService {
  bool _isWayland = Platform.environment['XDG_SESSION_TYPE'] == 'wayland';
  bool lastInjectionWasFallback = false;

  Future<bool> injectText(String text, {String method = 'dotool'}) async {
    lastInjectionWasFallback = false;
    print('DEBUG: [Injection] Injecting text using method: $method (Wayland: $_isWayland)');
    
    if (method == 'Clipboard') {
      return await _injectClipboard(text);
    }

    if (_isWayland) {
      return await _injectWayland(text);
    } else {
      return await _injectX11(text);
    }
  }

  Future<bool> _injectClipboard(String text) async {
    print('DEBUG: [Injection] Setting clipboard data');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      print('DEBUG: [Injection] Clipboard data set successfully');
    } catch (e) {
      print('DEBUG: [Injection] Failed to set clipboard data: $e');
      return false;
    }
    
    // Optional: simulate Ctrl+V
    print('DEBUG: [Injection] Attempting to simulate Ctrl+V...');
    bool pasteSuccess = false;
    if (_isWayland) {
      pasteSuccess = await _tryRun('dotool', [], stdinText: 'key ctrl+v\n');
      if (!pasteSuccess) {
        pasteSuccess = await _tryRun('ydotool', ['key', '29:1', '47:1', '47:0', '29:0']);
      }
      if (!pasteSuccess) {
        pasteSuccess = await _tryRun('wtype', ['-M', 'ctrl', 'v']);
      }
    } else {
      pasteSuccess = await _tryRun('xdotool', ['key', 'ctrl+v']);
    }

    if (pasteSuccess) {
      print('DEBUG: [Injection] Ctrl+V simulation succeeded');
    } else {
      print('DEBUG: [Injection] Ctrl+V simulation failed');
    }
    
    return true; // Consider success if clipboard was set
  }

  Future<bool> _tryRun(String command, List<String> args, {String? stdinText}) async {
    try {
      // For ydotool, ensure we point to the correct socket if it exists
      Map<String, String> env = Map.from(Platform.environment);
      if (command.contains('ydotool')) {
        if (!env.containsKey('YDOTOOL_SOCKET')) {
          // Check standard locations in order of preference
          final userUid = Platform.environment['USER_ID'] ?? '1000';
          final possibleSockets = [
            '/run/user/$userUid/.ydotool_socket',
            '/run/user/0/.ydotool_socket',
            '/tmp/.ydotool_socket',
          ];

          for (final path in possibleSockets) {
            if (await File(path).exists()) {
              env['YDOTOOL_SOCKET'] = path;
              break;
            }
          }
        }
      }

      if (stdinText != null) {
        print('DEBUG: [Injection] Running: echo "$stdinText" | $command ${args.join(' ')} (Socket: ${env['YDOTOOL_SOCKET']})');
        final process = await Process.start(command, args, environment: env);
        process.stdin.write(stdinText);
        await process.stdin.close();
        
        final exitCode = await process.exitCode;
        if (exitCode == 0) return true;
        return false;
      } else {
        print('DEBUG: [Injection] Running: $command ${args.join(' ')} (Socket: ${env['YDOTOOL_SOCKET']})');
        final result = await Process.run(command, args, environment: env);
        return result.exitCode == 0;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> _injectX11(String text) async {
    bool success = await _tryRun('xdotool', ['type', '--clearmodifiers', text]);
    if (!success) {
      print('DEBUG: [Injection] X11 injection failed. Is xdotool installed?');
      // Fallback to clipboard
      return await _injectClipboard(text);
    }
    return true;
  }

  Future<bool> _injectWayland(String text) async {
    print('DEBUG: [Injection] Attempting Wayland injection...');
    
    // Escape or sanitize text for shell safety - replace newlines with spaces
    final sanitizedText = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    print('DEBUG: [Injection] Sanitized text: "$sanitizedText"');
    
    // Try ydotool first - it's the most reliable on KDE (wtype doesn't work on KDE)
    bool success = await _tryRun('ydotool', ['type', '--', sanitizedText]);
    
    // Try wtype as fallback (works on GNOME/Sway but NOT on KDE)
    if (!success) {
      success = await _tryRun('wtype', ['--', sanitizedText]);
    }
    
    // Try dotool as last resort
    if (!success) {
      success = await _tryRun('dotool', [], stdinText: 'type $sanitizedText\n');
    }
    
    if (success) {
      print('DEBUG: [Injection] Wayland injection succeeded');
      return true;
    } else {
      print('DEBUG: [Injection] All Wayland injection tools failed. Is dotool, ydotool, or wtype installed?');
      // Final fallback: copy to clipboard
      print('DEBUG: [Injection] Falling back to Clipboard...');
      lastInjectionWasFallback = true;
      return await _injectClipboard(text);
    }
  }
}
