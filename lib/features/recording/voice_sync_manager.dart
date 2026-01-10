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

  WhisperEngine? _whisper;
  VadEngine? _vad;
  DateTime? _recordingStartTime;

  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  final _stateController = StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get stateStream => _stateController.stream;

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

    _hotkey.pttStateStream.listen((isPressed) {
      if (_settings.recordingMode != 'PTT') return;
      if (isPressed) {
        startRecording();
      } else {
        stopRecording();
      }
    });

    _audio.samplesStream.listen(_handleAudioSamples);
  }

  void _handleAudioSamples(List<double> samples) {
    if (_settings.recordingMode == 'Live') {
      _processLiveVAD(samples);
      return;
    }

    if (_state != RecordingState.recording) return;

    _audioBuffer.addAll(samples);
  }

  DateTime? _lastSpeechTime;
  bool _isCurrentlySpeaking = false;

  void _processLiveVAD(List<double> samples) {
    _audioBuffer.addAll(samples);
    
    // In Live mode, we use VAD to trigger recording
    if (_vad != null) {
      final isSpeech = _vad!.isSpeech(samples);
      
      if (isSpeech) {
        _lastSpeechTime = DateTime.now();
        if (!_isCurrentlySpeaking) {
          _isCurrentlySpeaking = true;
          if (_state == RecordingState.idle) {
            startRecording();
          }
        }
      } else {
        if (_isCurrentlySpeaking && _lastSpeechTime != null) {
          // Wait for 500ms of silence before stopping
          if (DateTime.now().difference(_lastSpeechTime!).inMilliseconds > 500) {
            _isCurrentlySpeaking = false;
            if (_state == RecordingState.recording) {
              stopRecording();
            }
          }
        }
      }
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

  Future<void> startRecording() async {
    print('DEBUG: VoiceSyncManager.startRecording() called, current state: $_state');
    if (_state != RecordingState.idle) {
      print('DEBUG: startRecording ignored because state is not idle');
      return;
    }
    
    try {
      print('DEBUG: Clearing audio buffer and starting audio capture...');
      _audioBuffer.clear();
      onInterimResult?.call('');
      _recordingStartTime = DateTime.now();
      await _audio.start();
      print('DEBUG: Audio capture started successfully');
      _state = RecordingState.recording;
      _stateController.add(_state);
    } catch (e, stack) {
      print('DEBUG: Failed to start recording: $e');
      print('DEBUG: Stack trace: $stack');
    }
  }

  Future<void> stopRecording() async {
    print('DEBUG: VoiceSyncManager.stopRecording() called, current state: $_state');
    if (_state != RecordingState.recording) {
      print('DEBUG: stopRecording ignored because state is not recording');
      return;
    }

    print('DEBUG: Stopping recording and starting processing...');
    final endTime = DateTime.now();
    _state = RecordingState.processing;
    _stateController.add(_state);
    
    try {
      await _audio.stop();
      print('DEBUG: Audio capture stopped. Buffer size: ${_audioBuffer.length} samples');

      if (_audioBuffer.isEmpty) {
        print('DEBUG: Audio buffer is empty, nothing to transcribe');
        _state = RecordingState.idle;
        _stateController.add(_state);
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
    _stateController.add(_state);
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
