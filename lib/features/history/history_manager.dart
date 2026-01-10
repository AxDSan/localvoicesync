import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'history_entry.dart';

class HistoryManager extends StateNotifier<List<HistoryEntry>> {
  HistoryManager() : super([]) {
    _loadHistory();
  }

  static const String _historyKey = 'transcription_history';
  static const int _maxHistorySize = 100;

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);
      
      if (historyJson != null) {
        final List<dynamic> jsonList = jsonDecode(historyJson);
        state = jsonList
            .map((json) => HistoryEntry.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      state = [];
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(state.map((entry) => entry.toJson()).toList());
      await prefs.setString(_historyKey, historyJson);
    } catch (e) {
      // Handle save error silently for now
    }
  }

  Future<void> addEntry(HistoryEntry entry) async {
    state = [entry, ...state];
    
    // Keep only the last _maxHistorySize entries
    if (state.length > _maxHistorySize) {
      state = state.sublist(0, _maxHistorySize);
    }
    
    await _saveHistory();
  }

  Future<void> deleteEntry(String id) async {
    state = state.where((entry) => entry.id != id).toList();
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    state = [];
    await _saveHistory();
  }

  Future<void> updateEntry(HistoryEntry entry) async {
    state = [
      for (final e in state)
        if (e.id == entry.id) entry else e,
    ];
    await _saveHistory();
  }
}
