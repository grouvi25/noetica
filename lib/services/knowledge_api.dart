import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/knowledge_index_models.dart';
import '../data/models.dart';
import 'api_config.dart';
import 'auth_service.dart';

class KnowledgeApiException implements Exception {
  KnowledgeApiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => 'KnowledgeApiException($status): $message';
}

/// Calls `/knowledge/reindex` to get AI-suggested folders + semantic
/// links for every entry. Body is truncated to ~400 chars per note
/// server-side, so we can safely send the full text here.
class KnowledgeApi {
  KnowledgeApi({
    String? backendBaseUrl,
    AuthService? auth,
    http.Client? httpClient,
  })  : _baseUrl = (backendBaseUrl ?? kDefaultBackendUrl).replaceAll(
          RegExp(r'/+$'),
          '',
        ),
        _auth = auth,
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final AuthService? _auth;
  final http.Client _http;

  Future<KnowledgeIndex> reindex(
    List<Entry> entries, {
    int maxFolders = 6,
  }) async {
    var token = _auth?.current?.accessToken;
    if (token == null || token.isEmpty) {
      token = (await _auth?.restore())?.accessToken;
    }
    if (!kDevSkipAuth && (token == null || token.isEmpty)) {
      throw KnowledgeApiException(
        'Сессия ещё не готова, попробуй чуть позже.',
        status: 401,
      );
    }

    final notes = entries
        .where((e) => !e.isDeleted)
        .map(
          (e) => {
            'id': e.id,
            'title': e.title,
            'body': e.body,
            'tags': e.tags,
          },
        )
        .toList();

    final url = Uri.parse('$_baseUrl/knowledge/reindex');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final body = jsonEncode({
      'notes': notes,
      'max_folders': maxFolders,
    });

    final response = await _http.post(url, headers: headers, body: body);
    if (response.statusCode == 401) {
      throw KnowledgeApiException(
        'Сессия истекла. Обновите страницу и попробуйте снова.',
        status: 401,
      );
    }
    if (response.statusCode >= 400) {
      throw KnowledgeApiException(
        response.body.isNotEmpty ? response.body : 'Reindex failed',
        status: response.statusCode,
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, Object?>;
    final folders = ((decoded['folders'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final nodes = ((decoded['nodes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => IndexedNode.fromJson(e.cast<String, Object?>()))
        .toList();
    return KnowledgeIndex(
      folders: folders,
      nodes: nodes,
      model: (decoded['model'] as String?) ?? '',
      indexedAt: DateTime.now(),
    );
  }

  void close() => _http.close();
}
