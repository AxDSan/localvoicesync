import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:record/record.dart';

class AudioCaptureService {
  final AudioRecorder _record = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  
  final _samplesController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get samplesStream => _samplesController.stream;

  final _volumeController = StreamController<double>.broadcast();
  Stream<double> get volumeStream => _volumeController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<void> start() async {
    if (_isRecording) return;

    if (await _record.hasPermission()) {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      final stream = await _record.startStream(config);
      
      _subscription = stream.listen((Uint8List data) {
        // Convert PCM16 (Int16) to Float32 [-1.0, 1.0]
        final floatSamples = <double>[];
        double maxAbs = 0;
        for (var i = 0; i < data.length; i += 2) {
          if (i + 1 < data.length) {
            // Little-endian PCM16
            int sample = data[i] | (data[i + 1] << 8);
            if (sample > 32767) sample -= 65536;
            final floatSample = sample / 32768.0;
            floatSamples.add(floatSample);
            maxAbs = math.max(maxAbs, floatSample.abs());
          }
        }
        _samplesController.add(floatSamples);
        _volumeController.add(maxAbs);
      });

      _isRecording = true;
    } else {
      throw Exception('Microphone permission denied');
    }
  }

  Future<void> stop() async {
    if (!_isRecording) return;

    await _subscription?.cancel();
    _subscription = null;
    await _record.stop();
    _isRecording = false;
  }

  void dispose() {
    stop();
    _samplesController.close();
    _record.dispose();
  }
}
