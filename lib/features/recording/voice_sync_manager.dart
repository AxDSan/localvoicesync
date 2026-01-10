import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/whisper/whisper_engine.dart';
import '../../core/vad/vad_engine.dart';
import '../../core/audio/audio_capture_service.dart';
import '../../core/text_injection/text_injection_service.dart';
import '../../core/hotkey/hotkey_service.dart';
import '../../core/llm/ollama_client.dart';
import '../history/history_entry.dart';
import '../settings/settings_service.dart';
import '../history/history_manager.dart';

enum RecordingState { idle, recording, processing }

class VoiceSyncManager {
  final SettingsService _settings;
  final HistoryManager _history;
  final AudioCaptureService _audio = AudioCaptureService();
  AudioCaptureService get audioService => _audio;
  final TextInjectionService _injector = TextInjectionService();
  final HotkeyService _hotkey = HotkeyService();
  HotkeyService get hotkeyService => _hotkey;
  OllamaClient _ollama;
  final _uuid = const Uuid();

  void Function(String)? onInterimResult;
  Timer? _interimTimer;
  bool _isProcessingInterim = false;

  WhisperEngine? _whisper;
  VadEngine? _vad;
  DateTime? _recordingStartTime;

  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  final _stateController = StreamController<RecordingState>.broadcast();
  
  /// Stream that forwards all state changes from the broadcast controller.
  /// Use `state` getter for current state.
  Stream<RecordingState> get stateStream => _stateController.stream;
  
  /// Callback to notify when mode should be switched (e.g., PTT hotkey pressed)
  void Function(String mode)? onModeSwitch;
  
  /// Callback to directly notify state changes (bypasses stream for immediate updates)
  void Function(RecordingState state)? onStateChange;

  final List<double> _audioBuffer = [];
  bool _isSpeechDetected = false;

  VoiceSyncManager(this._settings, this._history)
      : _ollama = OllamaClient(
          baseUrl: _settings.ollamaEndpoint,
          model: _settings.ollamaModel,
        );

  Future<void> initialize() async {
    print('DEBUG: Initializing VoiceSyncManager...');
    
    _settings.addListener(_onSettingsChanged);
    
    final projectRoot = Directory.current.path;
    final whisperLibPath = p.join(projectRoot, 'native', 'whisper', 'build', 'lib', 'libwhisper.so');
    final vadLibPath = p.join(projectRoot, 'native', 'vad', 'build', 'lib', 'libvad.so');
    final hotkeyLibPath = p.join(projectRoot, 'native', 'hotkey', 'build', 'lib', 'libhotkey.so');

    print('DEBUG: Using whisper library at: $whisperLibPath');
    print('DEBUG: Using VAD library at: $vadLibPath');
    print('DEBUG: Using hotkey library at: $hotkeyLibPath');

    try {
      await _hotkey.initialize(
        libraryPath: (await File(hotkeyLibPath).exists()) ? hotkeyLibPath : null,
      );
    } catch (e) {
      print('DEBUG: Hotkey initialization failed: $e');
      await _hotkey.initialize();
    }

    try {
      _whisper = await WhisperEngine.initialize(
        modelPath: _settings.whisperModelPath,
        libraryPath: (await File(whisperLibPath).exists()) ? whisperLibPath : null,
      );
      _lastWhisperModelPath = _settings.whisperModelPath;
      print('DEBUG: Whisper engine initialized.');
    } catch (e) {
      print('DEBUG: Whisper initialization failed: $e');
      // Try default path if the build path didn't work or exist
      _whisper = await WhisperEngine.initialize(
        modelPath: _settings.whisperModelPath,
      );
    }

    // Get absolute path for VAD model
    final docsDir = await getApplicationSupportDirectory();
    final vadModelPath = p.join(docsDir.path, 'models', 'silero_vad.onnx');

    try {
      _vad = await VadEngine.initialize(
        modelPath: vadModelPath,
        threshold: _settings.vadThreshold,
        libraryPath: (await File(vadLibPath).exists()) ? vadLibPath : null,
      );
      print('DEBUG: VAD engine initialized.');
    } catch (e) {
      print('DEBUG: VAD initialization failed: $e');
      _vad = await VadEngine.initialize(
        modelPath: vadModelPath,
        threshold: _settings.vadThreshold,
      );
    }

    _hotkey.setPttKey(_settings.pttKey);
    _hotkey.startPolling();

    _hotkey.pttStateStream.listen((isPressed) async {
      // Auto-switch to PTT mode when hotkey is pressed (regardless of current mode)
      if (isPressed && _settings.recordingMode != 'PTT') {
        print('DEBUG: PTT hotkey pressed, auto-switching to PTT mode');
        onModeSwitch?.call('PTT');
        // Wait a frame for Riverpod to rebuild before starting recording
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // Only handle recording if in PTT mode
      if (_settings.recordingMode != 'PTT') return;
      
      if (isPressed) {
        startRecording();
      } else {
        stopRecording();
      }
    });

    _audio.samplesStream.listen(_handleAudioSamples);
  }

  int _sampleDebugCounter = 0;
  
  void _handleAudioSamples(List<double> samples) {
    // Debug: log every 10th chunk
    _sampleDebugCounter++;
    if (_sampleDebugCounter % 10 == 0) {
      print('DEBUG: [Audio] mode=${_settings.recordingMode}, state=$_state, samples=${samples.length}, buffer=${_audioBuffer.length}');
    }
    
    if (_settings.recordingMode == 'Live') {
      _processLiveVAD(samples);
      return;
    }

    if (_state != RecordingState.recording) return;

    _audioBuffer.addAll(samples);
  }

  DateTime? _lastSpeechTime;
  bool _isCurrentlySpeaking = false;

  int _vadDebugCounter = 0;
  
  void _processLiveVAD(List<double> samples) {
    // In Live mode, we always want to see the volume spikes, which is handled
    // by AudioCaptureService.volumeStream.
    
    // We only add to _audioBuffer if we are recording or if we want some pre-roll
    if (_state == RecordingState.recording) {
      _audioBuffer.addAll(samples);
    } else if (_state == RecordingState.idle) {
      // Keep a small pre-roll buffer (e.g., 500ms)
      _audioBuffer.addAll(samples);
      const int maxPreRoll = 8000; // 0.5s at 16kHz
      if (_audioBuffer.length > maxPreRoll) {
        _audioBuffer.removeRange(0, _audioBuffer.length - maxPreRoll);
      }
    }
    
    // In Live mode, we use VAD to trigger recording
    if (_vad != null) {
      final isSpeech = _vad!.isSpeech(samples);
      
      // Debug log every ~1 second (assuming 100ms chunks = 10 per second)
      _vadDebugCounter++;
      if (_vadDebugCounter % 10 == 0) {
        print('DEBUG: [Live VAD] isSpeech=$isSpeech, speaking=$_isCurrentlySpeaking, state=$_state');
      }
      
      if (isSpeech) {
        _lastSpeechTime = DateTime.now();
        if (!_isCurrentlySpeaking) {
          print('DEBUG: [Live] Speech detected! Starting recording...');
          _isCurrentlySpeaking = true;
          if (_state == RecordingState.idle) {
            startRecording(isAutomatic: true);
          }
        }
      } else {
        if (_isCurrentlySpeaking && _lastSpeechTime != null) {
          // Wait for 1000ms of silence before stopping (more robust than 500ms)
          if (DateTime.now().difference(_lastSpeechTime!).inMilliseconds > 1000) {
            print('DEBUG: [Live] Silence detected, stopping');
            _isCurrentlySpeaking = false;
            if (_state == RecordingState.recording) {
              stopRecording();
            }
          }
        }
      }
    }
  }

  Future<void> _processInterim() async {
    // Allow processing even if we just moved to processing state to get that last bit of text
    if ((_state != RecordingState.recording && _state != RecordingState.processing) || 
        _audioBuffer.isEmpty || _isProcessingInterim) {
      print('DEBUG: [Interim] Skipping - state=$_state, bufferEmpty=${_audioBuffer.isEmpty}, processing=$_isProcessingInterim');
      return;
    }

    _isProcessingInterim = true;
    try {
      final samples = List<double>.from(_audioBuffer);
      print('DEBUG: [Interim] Processing ${samples.length} samples...');
      
      if (samples.length > 4000) { // Reduced to 0.25s for faster interim results
        final text = await _whisper!.transcribe(
          audioSamples: samples,
          language: _settings.language,
        );
        
        // Check state again as it might have changed during transcription
        if ((_state == RecordingState.recording || _state == RecordingState.processing) && text.isNotEmpty) {
          print('DEBUG: [Interim] Sending result: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
          onInterimResult?.call(text);
        } else {
          print('DEBUG: [Interim] Result not sent - state=$_state, textEmpty=${text.isEmpty}');
        }
      } else {
        print('DEBUG: [Interim] Not enough samples (${samples.length} < 4000)');
      }
    } catch (e) {
      print('DEBUG: Interim transcription failed: $e');
    } finally {
      _isProcessingInterim = false;
    }
  }

  Future<void> startListening() async {
    print('DEBUG: VoiceSyncManager.startListening() called');
    try {
      if (!_audio.isRecording) {
        await _audio.start();
        print('DEBUG: Passive audio capture started');
      }
    } catch (e) {
      print('DEBUG: Failed to start passive listening: $e');
    }
  }

  Future<void> stopListening() async {
    print('DEBUG: VoiceSyncManager.stopListening() called');
    try {
      if (_audio.isRecording && _state == RecordingState.idle && _settings.recordingMode != 'Live') {
        await _audio.stop();
        print('DEBUG: Passive audio capture stopped');
      }
    } catch (e) {
      print('DEBUG: Failed to stop passive listening: $e');
    }
  }

  Future<void> startRecording({bool isAutomatic = false}) async {
    print('DEBUG: VoiceSyncManager.startRecording(isAutomatic: $isAutomatic) called, current state: $_state');
    if (_state != RecordingState.idle) {
      print('DEBUG: startRecording ignored because state is not idle');
      return;
    }
    
    try {
      if (!isAutomatic && _settings.recordingMode != 'Live') {
        print('DEBUG: Clearing audio buffer...');
        _audioBuffer.clear();
      } else {
        print('DEBUG: Keeping existing buffer (${_audioBuffer.length} samples) for automatic/live recording');
      }

      onInterimResult?.call('');
      _recordingStartTime = DateTime.now();

      // Update state BEFORE awaiting audio start to catch early samples
      _state = RecordingState.recording;
      _stateController.add(_state);
      onStateChange?.call(_state);  // Immediate callback for UI

      await _audio.start();
      print('DEBUG: Audio capture started successfully');

      // Start interim results timer
      _interimTimer?.cancel();
      _interimTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        _processInterim();
      });
    } catch (e, stack) {
      print('DEBUG: Failed to start recording: $e');
      print('DEBUG: Stack trace: $stack');
      _state = RecordingState.idle;
      _stateController.add(_state);
      onStateChange?.call(_state);  // Immediate callback for UI
    }
  }

  Future<void> stopRecording() async {
    print('DEBUG: VoiceSyncManager.stopRecording() called, current state: $_state');
    if (_state != RecordingState.recording) {
      print('DEBUG: stopRecording ignored because state is not recording');
      return;
    }

    _interimTimer?.cancel();
    _interimTimer = null;

    print('DEBUG: Stopping recording and starting processing...');
    final endTime = DateTime.now();
    _state = RecordingState.processing;
    _stateController.add(_state);
    onStateChange?.call(_state);  // Immediate callback for UI
    
    try {
      await _audio.stop();
      print('DEBUG: Audio capture stopped. Buffer size: ${_audioBuffer.length} samples');

      if (_audioBuffer.isEmpty) {
        print('DEBUG: Audio buffer is empty, nothing to transcribe');
        _state = RecordingState.idle;
        _stateController.add(_state);
        onStateChange?.call(_state);  // Immediate callback for UI
        return;
      }

      // 1. Transcribe with Whisper
      print('DEBUG: Starting Whisper transcription with language: ${_settings.language}');
      final text = await _whisper!.transcribe(
        audioSamples: _audioBuffer,
        language: _settings.language,
      );
      print('DEBUG: Whisper transcription result: "$text"');
      
      if (text.trim().isNotEmpty) {
        onInterimResult?.call(text);
        // 2. Cleanup with Ollama (Optional)
        String finalOutput = text;
        try {
          print('DEBUG: Starting Ollama cleanup...');
          finalOutput = await _ollama.processTranscription(text);
          print('DEBUG: Ollama cleanup result: "$finalOutput"');
        } catch (e) {
          print('DEBUG: Ollama cleanup failed: $e');
        }

        // 3. Inject text
        print('DEBUG: Injecting text with method: ${_settings.injectionMethod}');
        await _injector.injectText(finalOutput, method: _settings.injectionMethod);
        print('DEBUG: Text injection completed');

        // 4. Save to history
        final entry = HistoryEntry(
          id: _uuid.v4(),
          rawText: text,
          cleanedText: finalOutput,
          timestamp: _recordingStartTime ?? DateTime.now(),
          durationMs: endTime.difference(_recordingStartTime ?? endTime).inMilliseconds,
          modelUsed: 'Whisper Turbo',
          llmModelUsed: _settings.ollamaModel,
        );
        await _history.addEntry(entry);
        print('DEBUG: History entry saved');
      }
    } catch (e, stack) {
      print('DEBUG: Processing error: $e');
      print('DEBUG: Stack trace: $stack');
    }

    _state = RecordingState.idle;
    _isCurrentlySpeaking = false; // Reset speech detection state
    _stateController.add(_state);
    onStateChange?.call(_state);  // Immediate callback for UI
    print('DEBUG: Returning to idle state');
  }

  String? _lastWhisperModelPath;

  void _onSettingsChanged() {
    print('DEBUG: Settings changed, updating engine configuration...');
    _hotkey.setPttKey(_settings.pttKey);
    
    // Refresh Ollama client with new settings
    _ollama = OllamaClient(
      baseUrl: _settings.ollamaEndpoint,
      model: _settings.ollamaModel,
    );
    
    if (_vad != null) {
      _vad!.setThreshold(_settings.vadThreshold);
    }
    
    // Check if whisper model changed
    if (_lastWhisperModelPath != _settings.whisperModelPath) {
      _lastWhisperModelPath = _settings.whisperModelPath;
      _reinitializeWhisper();
    }

    print('DEBUG: VAD Threshold updated to: ${_settings.vadThreshold}');
    print('DEBUG: PTT Key updated to: ${_settings.pttKey}');
  }

  Future<void> _reinitializeWhisper() async {
    print('DEBUG: Re-initializing Whisper engine with new model: ${_settings.whisperModelPath}');
    final projectRoot = Directory.current.path;
    final whisperLibPath = p.join(projectRoot, 'native', 'whisper', 'build', 'lib', 'libwhisper.so');
    
    final oldWhisper = _whisper;
    _whisper = null; // Mark as null while initializing
    oldWhisper?.dispose();

    try {
      _whisper = await WhisperEngine.initialize(
        modelPath: _settings.whisperModelPath,
        libraryPath: (await File(whisperLibPath).exists()) ? whisperLibPath : null,
      );
      print('DEBUG: Whisper engine re-initialized.');
    } catch (e) {
      print('DEBUG: Whisper re-initialization failed: $e');
    }
  }

  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _audio.dispose();
    _hotkey.dispose();
    _whisper?.dispose();
    _vad?.dispose();
    _stateController.close();
  }
}
