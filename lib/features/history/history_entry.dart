class HistoryEntry {
  final String id;
  final String rawText;
  final String cleanedText;
  final DateTime timestamp;
  final int durationMs;
  final String? modelUsed;
  final String? llmModelUsed;

  HistoryEntry({
    required this.id,
    required this.rawText,
    required this.cleanedText,
    required this.timestamp,
    required this.durationMs,
    this.modelUsed,
    this.llmModelUsed,
  });

  HistoryEntry copyWith({
    String? id,
    String? rawText,
    String? cleanedText,
    DateTime? timestamp,
    int? durationMs,
    String? modelUsed,
    String? llmModelUsed,
  }) {
    return HistoryEntry(
      id: id ?? this.id,
      rawText: rawText ?? this.rawText,
      cleanedText: cleanedText ?? this.cleanedText,
      timestamp: timestamp ?? this.timestamp,
      durationMs: durationMs ?? this.durationMs,
      modelUsed: modelUsed ?? this.modelUsed,
      llmModelUsed: llmModelUsed ?? this.llmModelUsed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rawText': rawText,
      'cleanedText': cleanedText,
      'timestamp': timestamp.toIso8601String(),
      'durationMs': durationMs,
      'modelUsed': modelUsed,
      'llmModelUsed': llmModelUsed,
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id'] as String,
      rawText: json['rawText'] as String,
      cleanedText: json['cleanedText'] as String? ?? json['rawText'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      durationMs: json['durationMs'] as int,
      modelUsed: json['modelUsed'] as String?,
      llmModelUsed: json['llmModelUsed'] as String?,
    );
  }
}
