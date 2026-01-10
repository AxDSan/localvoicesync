import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../features/recording/voice_sync_manager.dart';
import '../features/settings/settings_service.dart';
import '../features/history/history_manager.dart';
import '../features/history/history_entry.dart';

final settingsServiceProvider = ChangeNotifierProvider<SettingsService>((ref) {
  return SettingsService();
});

final historyManagerProvider =
    StateNotifierProvider<HistoryManager, List<HistoryEntry>>((ref) {
  return HistoryManager();
});

/// The VoiceSyncManager is a singleton that should persist across settings changes.
/// We use ref.read instead of ref.watch to avoid recreating the manager when settings change.
final voiceSyncManagerProvider = Provider<VoiceSyncManager>((ref) {
  // Use ref.read to get settings without watching (prevents recreation on settings change)
  final settings = ref.read(settingsServiceProvider);
  final history = ref.read(historyManagerProvider.notifier);
  final manager = VoiceSyncManager(settings, history);
  
  // Link interim results
  manager.onInterimResult = (text) {
    ref.read(interimResultsProvider.notifier).state = text;
  };
  
  // Link injection error
  manager.onInjectionError = (error) {
    ref.read(injectionErrorProvider.notifier).state = error;
    if (error != null) {
      // Clear error after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        ref.read(injectionErrorProvider.notifier).state = null;
      });
    }
  };
  
  // Link mode switch callback for auto-PTT
  manager.onModeSwitch = (mode) {
    ref.read(settingsServiceProvider).recordingMode = mode;
    // Stop listening when switching to PTT mode
    if (mode == 'PTT') {
      manager.stopListening();
    }
  };
  
  // Link state change callback for immediate UI updates
  manager.onStateChange = (state) {
    ref.read(recordingStateNotifierProvider.notifier).state = state;
  };
  
  return manager;
});

/// Direct state notifier for immediate UI updates (bypasses stream latency)
final recordingStateNotifierProvider = StateProvider<RecordingState>((ref) {
  return RecordingState.idle;
});

final recordingStateProvider = StreamProvider<RecordingState>((ref) {
  final manager = ref.watch(voiceSyncManagerProvider);
  return manager.stateStream;
});

final interimResultsProvider = StateProvider<String>((ref) => '');

final injectionErrorProvider = StateProvider<String?>((ref) => null);

final statusMessageProvider = Provider<String>((ref) {
  final error = ref.watch(injectionErrorProvider);
  if (error != null) return error;

  final interim = ref.watch(interimResultsProvider);
  if (interim.isNotEmpty) return interim;

  final state = ref.watch(recordingStateNotifierProvider);
  switch (state) {
    case RecordingState.idle:
      return 'Ready to capture';
    case RecordingState.recording:
      return 'Recording...';
    case RecordingState.processing:
      return 'Processing transcription...';
  }
});

final overlayControllerProvider = Provider<OverlayController>((ref) {
  return OverlayController(ref);
});

/// Controller for the overlay window (ghost window on KDE/Wayland).
/// 
/// This controller handles creating, showing, hiding, and communicating
/// with the secondary process overlay window. It includes retry logic
/// to handle the asynchronous nature of window initialization on Wayland.
class OverlayController {
  final Ref _ref;
  WindowController? _window;
  bool _isInitializing = false;
  bool _isWindowReady = false;
  
  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(milliseconds: 300);
  static const Duration _initialReadyDelay = Duration(milliseconds: 500);

  OverlayController(this._ref) {
    // Pre-initialize the overlay window so it's ready when needed
    _initializeOverlay();
    
    // Listen to the direct state notifier for immediate updates
    _ref.listen(recordingStateNotifierProvider, (previous, next) {
      print('DEBUG: OverlayController received state change: $next');
      _updateVisibility(next);
      
      // Clear interim results when returning to idle
      if (next == RecordingState.idle) {
        _ref.read(interimResultsProvider.notifier).state = '';
      }
    });

    _ref.listen(interimResultsProvider, (previous, next) {
      _safeInvokeMethod('updateInterimText', next);
    });
  }

  /// Safely invoke a method on the overlay window with retry logic.
  Future<void> _safeInvokeMethod(String method, dynamic argument) async {
    if (_window == null || !_isWindowReady) {
      print('DEBUG: OverlayController._safeInvokeMethod: Window not ready, skipping $method');
      return;
    }
    
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _window!.invokeMethod(method, argument);
        return; // Success
      } catch (e) {
        print('DEBUG: OverlayController._safeInvokeMethod attempt ${attempt + 1} failed: $e');
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay);
        }
      }
    }
    print('DEBUG: OverlayController._safeInvokeMethod: All retries exhausted for $method');
  }

  Future<void> _updateVisibility(RecordingState state) async {
    print('DEBUG: OverlayController._updateVisibility(state: $state)');
    
    if (state != RecordingState.idle) {
      // Need to show the overlay - wait for initialization if in progress
      await _ensureOverlayReady();
      
      if (_window != null && _isWindowReady) {
        print('DEBUG: Showing overlay window ${_window?.windowId}');
        
        // Show the window
        for (int attempt = 0; attempt < _maxRetries; attempt++) {
          try {
            await _window!.show();
            break;
          } catch (e) {
            print('DEBUG: Show attempt ${attempt + 1} failed: $e');
            if (attempt < _maxRetries - 1) {
              await Future.delayed(_retryDelay);
            }
          }
        }
        
        // Send current interim text
        await _safeInvokeMethod('updateInterimText', _ref.read(interimResultsProvider));
      }
    } else {
      // Hide the overlay
      if (_window != null && _isWindowReady) {
        print('DEBUG: Hiding overlay window');
        for (int attempt = 0; attempt < _maxRetries; attempt++) {
          try {
            await _window!.hide();
            break;
          } catch (e) {
            print('DEBUG: Hide attempt ${attempt + 1} failed: $e');
            if (attempt < _maxRetries - 1) {
              await Future.delayed(_retryDelay);
            }
          }
        }
      }
    }
  }
  
  /// Wait for the overlay to be ready, initializing if needed.
  Future<void> _ensureOverlayReady() async {
    // If already ready, nothing to do
    if (_window != null && _isWindowReady) return;
    
    // If initialization is in progress, wait for it
    if (_isInitializing) {
      print('DEBUG: OverlayController: Waiting for initialization to complete...');
      // Poll until initialization completes
      for (int i = 0; i < 20; i++) { // Max 2 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        if (!_isInitializing) break;
      }
    }
    
    // If still not ready, try to initialize
    if (_window == null && !_isInitializing) {
      await _initializeOverlay();
    }
  }

  Future<void> _initializeOverlay() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _isWindowReady = false;
    
    print('DEBUG: OverlayController._initializeOverlay: Starting...');
    
    try {
      _window = await WindowController.create(WindowConfiguration(
        arguments: jsonEncode({'type': 'overlay'}),
      ));
      
      print('DEBUG: OverlayController._initializeOverlay: Window created with ID ${_window?.windowId}');
      
      // Wait for the native window to be fully configured
      // This delay allows the GTK ghost window setup to complete
      await Future.delayed(_initialReadyDelay);
      
      // Verify the window is responsive
      bool verified = false;
      for (int attempt = 0; attempt < _maxRetries; attempt++) {
        try {
          // Try a benign operation to verify the window channel is ready
          await _window!.hide(); // Start hidden
          verified = true;
          break;
        } catch (e) {
          print('DEBUG: OverlayController._initializeOverlay: Verification attempt ${attempt + 1} failed: $e');
          await Future.delayed(_retryDelay);
        }
      }
      
      if (verified) {
        _isWindowReady = true;
        print('DEBUG: OverlayController._initializeOverlay: Window is ready!');
      } else {
        print('DEBUG: OverlayController._initializeOverlay: Window verification failed, will retry on next use');
        _window = null;
      }
      
    } catch (e, stack) {
      print('DEBUG: OverlayController._initializeOverlay: Error creating overlay: $e');
      print('DEBUG: Stack: $stack');
      _window = null;
    } finally {
      _isInitializing = false;
    }
  }
  
  /// Dispose of the overlay window if it exists.
  Future<void> dispose() async {
    if (_window != null) {
      try {
        // WindowController only has show/hide, so we just hide it
        await _window!.hide();
      } catch (e) {
        print('DEBUG: OverlayController.dispose: Error hiding window: $e');
      }
      _window = null;
      _isWindowReady = false;
    }
  }
}

final elapsedMsProvider = Provider<int>((ref) {
  // Simple implementation for now
  return 0;
});
