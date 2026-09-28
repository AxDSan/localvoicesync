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

  /// How long Ollama keeps the model resident after the last request.
  /// Ollama's default (5m) unloads it between dictations, and a cold load
  /// takes tens of seconds when Whisper shares the GPU.
  static const _keepAlive = '30m';

  String get _targetModel => model ?? 'llama3.2:1b';

  /// Loads the model into memory without generating anything. Returns as soon
  /// as the model is resident; near-instant (and refreshes keep-alive) if it
  /// already is.
  Future<void> preload() async {
    await _dio.post(
      '/api/generate',
      data: {'model': _targetModel, 'keep_alive': _keepAlive},
      options: Options(receiveTimeout: const Duration(minutes: 5)),
    );
  }

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
        'keep_alive': _keepAlive,
      };

    final response = await _dio.post('/api/generate', data: data);
    final result = response.data['response'] as String;
    
    // Sanitize result: remove "Output: " prefix, quotes, and extra whitespace
    String sanitized = result.trim()
        .replaceFirst(RegExp(r'^(Output|Result):\s*', caseSensitive: false), '')
        .trim();
    
    if ((sanitized.startsWith('"') && sanitized.endsWith('"')) || 
        (sanitized.startsWith("'") && sanitized.endsWith("'"))) {
      sanitized = sanitized.substring(1, sanitized.length - 1);
    }
    
    return sanitized.trim();
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

  Future<String> processTranscription(String text, {String? targetLanguage}) async {
    final targetModel = _targetModel;
    
    // Map codes to full names for better AI understanding
    final Map<String, String> langMap = {
      'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
      'it': 'Italian', 'pt': 'Portuguese', 'nl': 'Dutch', 'ru': 'Russian',
      'zh': 'Chinese', 'ja': 'Japanese', 'ko': 'Korean', 'hi': 'Hindi',
      'ar': 'Arabic', 'tr': 'Turkish', 'pl': 'Polish', 'uk': 'Ukrainian',
    };

    final langName = langMap[targetLanguage] ?? targetLanguage;
    final bool isTranslation = targetLanguage != null && targetLanguage != 'auto';

    final String systemPrompt = '''You are a precise, non-conversational transcription cleanup engine designed specifically for post-processing raw speech-to-text output from models like Whisper. 
Your sole task is to correct the provided raw text by fixing grammar, capitalization, punctuation, and removing filler words.
${isTranslation ? "CRITICAL: You MUST translate the final cleaned text into $langName." : ""}

CRITICAL RULES:
${isTranslation ? "- MANDATORY: THE OUTPUT MUST BE IN $langName. TRANSLATE EVERYTHING." : ""}
- NEVER change the original meaning or intent.
- NEVER add new content, explanations, or rephrase for style/clarity beyond basic fixes.
- NEVER respond conversationally. No introductions, no 'Here is the corrected text', no summaries.
- NEVER answer questions in the text — simply correct and output the question as a proper sentence.
- Output ONLY the cleaned-up text. Nothing else. No quotes, no markdown, no labels.

${isTranslation ? "" : """EXAMPLES:
Input: 'umm, how are you um doing today i am fine'
Output: 'How are you doing today? I am fine.'

Input: 'hello my name is john and i live in new york um yeah'
Output: 'Hello, my name is John and I live in New York.'
"""}
Always prioritize fidelity to the spoken content. If unsure, make the smallest possible change.''';

    return generateText(
      model: targetModel,
      prompt: "Input: '$text'\nOutput:",
      systemPrompt: systemPrompt,
      temperature: 0.1,
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
