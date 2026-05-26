import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'knowledge_index_models.dart';

/// Persists the AI-generated knowledge index (folders + node metadata)
/// in SharedPreferences as a JSON blob. Index payloads are small enough
/// (a few KB even with hundreds of notes) that we can stay in prefs
/// without bothering SQLite.
class KnowledgeIndexService {
  static const _kKey = 'noetica.knowledge_index.v1';
  static final _changes = StreamController<KnowledgeIndex>.broadcast();
  static Stream<KnowledgeIndex> get changes => _changes.stream;

  Future<KnowledgeIndex> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return KnowledgeIndex.empty();
    try {
      return KnowledgeIndex.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } catch (_) {
      return KnowledgeIndex.empty();
    }
  }

  Future<void> save(KnowledgeIndex index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(index.toJson()));
    if (!_changes.isClosed) _changes.add(index);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
    if (!_changes.isClosed) _changes.add(KnowledgeIndex.empty());
  }
}
