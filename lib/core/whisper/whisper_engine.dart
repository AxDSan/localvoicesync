import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import '../../native/whisper/whisper_bindings.dart';

enum WhisperStrategy {
  greedy(0),
  beamSearch(1);

  final int value;
  const WhisperStrategy(this.value);
}

class WhisperEngine {
  final SendPort _commandPort;
  bool _initialized = false;
  Map<String, dynamic>? _metadata;

  WhisperEngine._(this._commandPort, this._metadata) : _initialized = true;

  static Future<WhisperEngine> initialize({
    String modelPath = '',
    String? libraryPath,
  }) async {
    print('DEBUG: WhisperEngine.initialize(modelPath: $modelPath)');
    
    final resolvedLibraryPath = libraryPath ?? (Platform.isLinux ? 'libwhisper.so' : 'whisper.dll');
    final receivePort = ReceivePort();
    
    await Isolate.spawn(_whisperIsolate, [receivePort.sendPort, resolvedLibraryPath, modelPath]);
    
    final events = receivePort.asBroadcastStream();
    final commandPort = await events.first as SendPort;
    
    // Request metadata
    final metadataPort = ReceivePort();
    commandPort.send(['get_metadata', metadataPort.sendPort]);
    final metadata = await metadataPort.first as Map<String, dynamic>;
    
    return WhisperEngine._(commandPort, metadata);
  }

  Future<String> transcribe({
    required List<double> audioSamples,
    WhisperStrategy strategy = WhisperStrategy.greedy,
    String language = 'en',
    int nThreads = 4,
    bool translate = false,
  }) async {
    if (!_initialized) {
      throw WhisperException('Whisper engine not initialized');
    }

    print('DEBUG: WhisperEngine.transcribe called with ${audioSamples.length} samples');
    
    final responsePort = ReceivePort();
    _commandPort.send(_TranscribeRequest(
      responsePort: responsePort.sendPort,
      audioSamples: audioSamples,
      strategy: strategy,
      language: language,
      nThreads: nThreads,
      translate: translate,
    ));

    final result = await responsePort.first;
    if (result is String) {
      return result;
    } else if (result is WhisperException) {
      throw result;
    } else {
      throw WhisperException('Unknown error during transcription');
    }
  }

  static void _whisperIsolate(List<dynamic> args) async {
    final SendPort mainSendPort = args[0];
    final String libraryPath = args[1];
    final String modelPath = args[2];

    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    print('DEBUG: [Isolate] Opening library at $libraryPath');
    final lib = DynamicLibrary.open(libraryPath);
    final bindings = WhisperBindings(lib);
    
    print('DEBUG: [Isolate] Initializing whisper context with model: $modelPath');
    final cparams = bindings.contextDefaultParams();
    // Enable GPU support
    cparams.use_gpu = true;
    print('DEBUG: [Isolate] GPU support enabled: ${cparams.use_gpu}');
    
    final modelPtr = modelPath.toNativeUtf8();
    final context = bindings.initFromFileWithParams(modelPtr.cast(), cparams);
    calloc.free(modelPtr);

    if (context == nullptr) {
      print('DEBUG: [Isolate] Failed to load model');
      return;
    }

    print('DEBUG: [Isolate] Model loaded and ready');

    // Pre-calculate metadata
    final version = bindings.version().cast<Utf8>().toDartString();
    final vocabSize = bindings.nVocab(context);
    final textContextSize = bindings.nTextCtx(context);
    final audioContextSize = bindings.nAudioCtx(context);
    final isMultilingual = bindings.isMultilingual(context) != 0;

    await for (final msg in commandPort) {
      if (msg is _TranscribeRequest) {
        try {
          print('DEBUG: [Isolate] Starting transcription task...');
          final params = bindings.fullDefaultParams(msg.strategy.value);
          params.strategy = msg.strategy.value;
          params.n_threads = msg.nThreads;
          params.translate = msg.translate;
          params.detect_language = msg.language == 'auto';

          final langPtr = msg.language.toNativeUtf8();
          params.language = langPtr.cast();

          final samplesPtr = calloc<Float>(msg.audioSamples.length);
          for (var i = 0; i < msg.audioSamples.length; i++) {
            samplesPtr[i] = msg.audioSamples[i];
          }

          final result = bindings.full(
            context,
            params,
            samplesPtr,
            msg.audioSamples.length,
          );

          malloc.free(langPtr);
          calloc.free(samplesPtr);

          if (result != 0) {
            msg.responsePort.send(WhisperException('Whisper transcription failed with code $result'));
            continue;
          }

          final nSegments = bindings.fullNSegments(context);
          final buffer = StringBuffer();

          for (var i = 0; i < nSegments; i++) {
            final textPtr = bindings.fullGetSegmentText(context, i);
            final text = textPtr.cast<Utf8>().toDartString();
            buffer.write(text);
            buffer.write(' ');
          }

          final finalResult = buffer.toString().trim();
          print('DEBUG: [Isolate] Transcription finished, result length: ${finalResult.length}');
          msg.responsePort.send(finalResult);
        } catch (e) {
          msg.responsePort.send(WhisperException('Transcription error: $e'));
        }
      } else if (msg is List && msg[0] == 'get_metadata') {
        final SendPort replyPort = msg[1];
        replyPort.send({
          'version': version,
          'vocabSize': vocabSize,
          'textContextSize': textContextSize,
          'audioContextSize': audioContextSize,
          'isMultilingual': isMultilingual,
        });
      } else if (msg == 'dispose') {
        bindings.free(context);
        break;
      }
    }
  }

  String get version => _metadata?['version'] ?? 'unknown';
  int get vocabSize => _metadata?['vocabSize'] ?? 0;
  int get textContextSize => _metadata?['textContextSize'] ?? 0;
  int get audioContextSize => _metadata?['audioContextSize'] ?? 0;
  bool get isMultilingual => _metadata?['isMultilingual'] ?? false;

  void dispose() {
    if (_initialized) {
      _commandPort.send('dispose');
      _initialized = false;
    }
  }
}

class _TranscribeRequest {
  final SendPort responsePort;
  final List<double> audioSamples;
  final WhisperStrategy strategy;
  final String language;
  final int nThreads;
  final bool translate;

  _TranscribeRequest({
    required this.responsePort,
    required this.audioSamples,
    required this.strategy,
    required this.language,
    required this.nThreads,
    required this.translate,
  });
}

class WhisperSegment {
  final String text;
  final int startTimeMs;
  final int endTimeMs;
  final List<String> tokens;

  WhisperSegment({
    required this.text,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.tokens,
  });

  double get durationSeconds => (endTimeMs - startTimeMs) / 1000.0;
}

class WhisperException implements Exception {
  final String message;
  WhisperException(this.message);

  @override
  String toString() => 'WhisperException: $message';
}
