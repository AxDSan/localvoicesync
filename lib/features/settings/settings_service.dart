import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class SettingsService extends ChangeNotifier {
  static const String _keyModelPath = 'whisper_model_path';
  static const String _keyVADThreshold = 'vad_threshold';
  static const String _keyPTTKey = 'ptt_key';
  static const String _keyOllamaEndpoint = 'ollama_endpoint';
  static const String _keyOllamaModel = 'ollama_model';
  static const String _keyInjectionMethod = 'injection_method';
  static const String _keyAutoCleanup = 'auto_cleanup';
  static const String _keyLanguage = 'language';
  static const String _keyRecordingMode = 'recording_mode';

  late SharedPreferences _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _ensureAssetsCopied();
    await _checkExternalModels();
    notifyListeners();
  }

  Future<void> _checkExternalModels() async {
    final externalPath = '/home/aj/.local/share/localvoicesync/models/';
    final externalDir = Directory(externalPath);
    if (await externalDir.exists()) {
      print('DEBUG: Found external models directory at $externalPath');
      // If we haven't manually set a model path yet, and a better one exists externally, 
      // we could point to it, but for now we'll just make them available for selection.
    }
  }

  Future<List<String>> getAvailableModels() async {
    final List<String> models = [];
    
    // Check app-specific models
    final docsDir = await getApplicationSupportDirectory();
    final appModelsDir = Directory(p.join(docsDir.path, 'models'));
    if (await appModelsDir.exists()) {
      await for (final file in appModelsDir.list()) {
        if (file.path.endsWith('.bin')) {
          models.add(file.path);
        }
      }
    }

    // Check external models
    final externalPath = '/home/aj/.local/share/localvoicesync/models/';
    final externalDir = Directory(externalPath);
    if (await externalDir.exists()) {
      await for (final file in externalDir.list()) {
        if (file.path.endsWith('.bin')) {
          models.add(file.path);
        }
      }
    }

    return models.toSet().toList(); // Unique paths
  }

  Future<void> _ensureAssetsCopied() async {
    // Check for distil model first as it's superior
    final externalDistilPath = '/home/aj/.local/share/localvoicesync/models/ggml-distil-large-v3.5.bin';
    if (await File(externalDistilPath).exists()) {
      print('DEBUG: Found superior Distil-Whisper model in external path: $externalDistilPath');
      // If we haven't manually set a model path yet, point to the distil one
      if (_prefs.getString(_keyModelPath) == null || 
          _prefs.getString(_keyModelPath)!.contains('ggml-large-v3-turbo.bin')) {
        await _prefs.setString(_keyModelPath, externalDistilPath);
      }
    } else {
      // Fallback to turbo in external path
      final externalTurboPath = '/home/aj/.local/share/localvoicesync/models/ggml-large-v3-turbo.bin';
      if (await File(externalTurboPath).exists()) {
        print('DEBUG: Found Whisper model in external path: $externalTurboPath');
        if (_prefs.getString(_keyModelPath) == null) {
          await _prefs.setString(_keyModelPath, externalTurboPath);
        }
      }
    }

    final docsDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(docsDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    // Copy Whisper model from assets only if not already set to a valid path
    final currentModelPath = _prefs.getString(_keyModelPath);
    final whisperModelFile = File(p.join(modelsDir.path, 'ggml-large-v3-turbo.bin'));
    
    if (currentModelPath == null || !await File(currentModelPath).exists()) {
      if (!await whisperModelFile.exists()) {
        print('DEBUG: Copying Whisper model to ${whisperModelFile.path}');
        final data = await rootBundle.load('assets/models/ggml-large-v3-turbo.bin');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await whisperModelFile.writeAsBytes(bytes);
      }
      if (_prefs.getString(_keyModelPath) == null) {
        await _prefs.setString(_keyModelPath, whisperModelFile.path);
      }
    }

    // Copy VAD model
    final vadModelFile = File(p.join(modelsDir.path, 'silero_vad.onnx'));
    if (!await vadModelFile.exists()) {
      print('DEBUG: Copying VAD model to ${vadModelFile.path}');
      final data = await rootBundle.load('assets/models/silero_vad.onnx');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await vadModelFile.writeAsBytes(bytes);
    }
  }

  String get whisperModelPath => _prefs.getString(_keyModelPath) ?? '';
  set whisperModelPath(String value) {
    _prefs.setString(_keyModelPath, value);
    notifyListeners();
  }

  double get vadThreshold => _prefs.getDouble(_keyVADThreshold) ?? 0.5;
  set vadThreshold(double value) {
    _prefs.setDouble(_keyVADThreshold, value);
    notifyListeners();
  }

  String get pttKey => _prefs.getString(_keyPTTKey) ?? 'F12';
  set pttKey(String value) {
    _prefs.setString(_keyPTTKey, value);
    notifyListeners();
  }

  String get ollamaEndpoint => _prefs.getString(_keyOllamaEndpoint) ?? 'http://localhost:11434';
  set ollamaEndpoint(String value) {
    _prefs.setString(_keyOllamaEndpoint, value);
    notifyListeners();
  }

  String get ollamaModel => _prefs.getString(_keyOllamaModel) ?? 'llama3';
  set ollamaModel(String value) {
    _prefs.setString(_keyOllamaModel, value);
    notifyListeners();
  }

  String get injectionMethod => _prefs.getString(_keyInjectionMethod) ?? 'dotool';
  set injectionMethod(String value) {
    _prefs.setString(_keyInjectionMethod, value);
    notifyListeners();
  }

  bool get autoCleanup => _prefs.getBool(_keyAutoCleanup) ?? true;
  set autoCleanup(bool value) {
    _prefs.setBool(_keyAutoCleanup, value);
    notifyListeners();
  }

  String get language => _prefs.getString(_keyLanguage) ?? 'en';
  set language(String value) {
    _prefs.setString(_keyLanguage, value);
    notifyListeners();
  }

  String get recordingMode => _prefs.getString(_keyRecordingMode) ?? 'Manual';
  set recordingMode(String value) {
    _prefs.setString(_keyRecordingMode, value);
    notifyListeners();
  }
}
