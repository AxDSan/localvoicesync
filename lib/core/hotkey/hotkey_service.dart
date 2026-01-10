import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../native/hotkey/hotkey_bindings.dart';

class HotkeyService {
  HotkeyBindings? _bindings;
  int _pttKeyCode = 0;
  bool _isPressed = false;
  Timer? _timer;

  final _stateController = StreamController<bool>.broadcast();
  Stream<bool> get pttStateStream => _stateController.stream;

  HotkeyService();

  Future<void> initialize({String? libraryPath}) async {
    if (_bindings != null) return;

    print('DEBUG: HotkeyService.initialize(libraryPath: $libraryPath)');
    final DynamicLibrary lib;
    try {
      if (libraryPath != null) {
        print('DEBUG: Opening Hotkey library at $libraryPath');
        lib = DynamicLibrary.open(libraryPath);
      } else {
        final libName = Platform.isLinux ? 'libhotkey.so' : 'hotkey.dll';
        print('DEBUG: Opening Hotkey library $libName');
        lib = DynamicLibrary.open(libName);
      }
    } catch (e) {
      print('DEBUG: Failed to open Hotkey library: $e');
      rethrow;
    }

    _bindings = HotkeyBindings(lib);
    print('DEBUG: Hotkey service initialized successfully');
  }

  void setPttKey(String keysymName) {
    if (_bindings == null) {
      print('DEBUG: HotkeyService.setPttKey called before initialize');
      return;
    }
    final namePtr = keysymName.toNativeUtf8();
    _pttKeyCode = _bindings!.x11_get_keycode(namePtr.cast());
    malloc.free(namePtr);
    print('DEBUG: PTT KeyCode for $keysymName: $_pttKeyCode');
  }

  Future<String?> getNextPressedKey() async {
    if (_bindings == null) return null;

    final completer = Completer<String?>();
    Timer? listenTimer;

    listenTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final code = _bindings!.x11_get_pressed_keycode();
      if (code != 0) {
        final namePtr = _bindings!.x11_get_keysym_name(code);
        if (namePtr != nullptr) {
          final name = namePtr.cast<Utf8>().toDartString();
          timer.cancel();
          completer.complete(name);
        }
      }
    });

    // Timeout after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        listenTimer?.cancel();
        completer.complete(null);
      }
    });

    return completer.future;
  }

  void startPolling() {
    if (_bindings == null) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (_pttKeyCode == 0) return;

      final pressed = _bindings!.x11_is_key_pressed(_pttKeyCode);
      if (pressed != _isPressed) {
        _isPressed = pressed;
        _stateController.add(_isPressed);
      }
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stopPolling();
    _stateController.close();
  }
}
