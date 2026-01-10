import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OllamaClient {
  final Dio _dio;
  final String baseUrl;
  final String? model;

  OllamaClient({
    String baseUrl = 'http://localhost:11434',
    this.model,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ));

  Future<List<String>> getModels() async {
    try {
      final response = await _dio.get('/api/tags');
      final models = response.data['models'] as List;
      return models.map((model) => model['name'] as String).toList();
    } catch (e) {
      throw OllamaException('Failed to fetch models: $e');
    }
  }

  Future<String> generateText({
    required String model,
    required String prompt,
    String? systemPrompt,
    int? numPredict,
    double temperature = 0.7,
  }) async {
    print('DEBUG: OllamaClient.generateText hit: ${baseUrl}/api/generate with model: $model');
    try {
      final data = {
        'model': model,
        'prompt': prompt,
        'stream': false,
        'temperature': temperature,
        if (systemPrompt != null) 'system': systemPrompt,
        if (numPredict != null) 'num_predict': numPredict,
      };

      final response = await _dio.post('/api/generate', data: data);
      return response.data['response'] as String;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        // Log available models to help the user debug
        try {
          final models = await getModels();
          print('DEBUG: Ollama 404 - Model "$model" not found. Available models: $models');
        } catch (_) {}
      }
      throw OllamaException('Failed to generate text: $e');
    }
  }

  Future<String> processTranscription(String text) async {
    final targetModel = model ?? 'llama3';
    final prompt = '''Clean up the following speech-to-text transcription. 
Fix capitalization, punctuation, and obvious speech recognition errors. 
Return only the cleaned text, no additional commentary.

Original text: $text''';

    return generateText(
      model: targetModel,
      prompt: prompt,
      systemPrompt: 'You are a helpful assistant that cleans up speech-to-text transcriptions.',
    );
  }

  Future<void> pullModel({
    required String model,
    Function(int progress)? onProgress,
  }) async {
    try {
      final data = {'name': model, 'stream': true};

      await _dio.post(
        '/api/pull',
        data: data,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            final progress = ((received / total) * 100).toInt();
            onProgress(progress);
          }
        },
      );
    } catch (e) {
      throw OllamaException('Failed to pull model: $e');
    }
  }

  Future<bool> checkConnection() async {
    try {
      await _dio.get('/');
      return true;
    } catch (e) {
      return false;
    }
  }
}

class OllamaException implements Exception {
  final String message;
  OllamaException(this.message);

  @override
  String toString() => 'OllamaException: $message';
}

final ollamaClientProvider = Provider<OllamaClient>((ref) {
  return OllamaClient();
});
