import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../native/vad_bindings.dart';

class VadEngine {
  final VadBindings _bindings;
  Pointer<vad_context>? _context;
  final int sampleRate;
  final int frameSize;
  double threshold;

  VadEngine._(this._bindings, this._context, this.sampleRate, this.frameSize, this.threshold);

  static Future<VadEngine> initialize({
    required String modelPath,
    String? libraryPath,
    int sampleRate = 16000,
    int frameSize = 512,
    double threshold = 0.5,
  }) async {
    print('DEBUG: VadEngine.initialize(modelPath: $modelPath)');
    final DynamicLibrary lib;
    try {
      if (libraryPath != null) {
        print('DEBUG: Opening VAD library at $libraryPath');
        lib = DynamicLibrary.open(libraryPath);
      } else {
        final libName = Platform.isLinux ? 'libvad.so' : 'vad.dll';
        print('DEBUG: Opening VAD library $libName');
        lib = DynamicLibrary.open(libName);
      }
    } catch (e) {
      print('DEBUG: Failed to open VAD library: $e');
      rethrow;
    }

    final bindings = VadBindings(lib);

    print('DEBUG: Configuring VAD...');
    final config = calloc<vad_config>();
    config.ref.sample_rate = sampleRate;
    config.ref.frame_size = frameSize;
    config.ref.threshold = threshold;
    config.ref.min_silence_duration_ms = 100;
    config.ref.speech_pad_ms = 30;

    print('DEBUG: Converting model path to native string...');
    final modelPathPtr = modelPath.toNativeUtf8();
    
    print('DEBUG: Initializing VAD context from file: $modelPath');
    final context = bindings.vad_init(modelPathPtr.cast(), config.ref);
    calloc.free(modelPathPtr);
    calloc.free(config);

    if (context == nullptr) {
      print('DEBUG: vad_init returned nullptr');
      throw Exception('Failed to initialize VAD engine');
    }

    print('DEBUG: VAD engine initialized successfully');
    return VadEngine._(bindings, context, sampleRate, frameSize, threshold);
  }

  void setThreshold(double threshold) {
    this.threshold = threshold;
  }

  bool isSpeech(List<double> samples) {
    final prob = process(samples);
    return prob >= threshold;
  }

  double process(List<double> samples) {
    if (_context == nullptr) throw Exception('VAD engine disposed');
    
    final samplesPtr = calloc<Float>(samples.length);
    for (var i = 0; i < samples.length; i++) {
      samplesPtr[i] = samples[i];
    }

    final prob = _bindings.vad_process(_context!, samplesPtr, samples.length);
    calloc.free(samplesPtr);
    
    return prob;
  }

  void reset() {
    if (_context != nullptr) {
      _bindings.vad_reset(_context!);
    }
  }

  void dispose() {
    if (_context != nullptr) {
      _bindings.vad_free(_context!);
      _context = nullptr;
    }
  }
}
