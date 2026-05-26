import 'package:flutter/foundation.dart';

/// AI-generated metadata for a single Entry: which folder it belongs to,
/// a one-sentence summary, and up to 3 related entry ids.
@immutable
class IndexedNode {
  const IndexedNode({
    required this.id,
    required this.folder,
    required this.summary,
    required this.tags,
    required this.relatedIds,
  });

  final String id;
  final String folder;
  final String summary;
  final List<String> tags;
  final List<String> relatedIds;

  factory IndexedNode.fromJson(Map<String, Object?> j) => IndexedNode(
        id: (j['id'] as String?) ?? '',
        folder: (j['folder'] as String?) ?? 'Misc',
        summary: (j['summary'] as String?) ?? '',
        tags: ((j['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        relatedIds: ((j['related_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'folder': folder,
        'summary': summary,
        'tags': tags,
        'related_ids': relatedIds,
      };
}

@immutable
class KnowledgeIndex {
  const KnowledgeIndex({
    required this.folders,
    required this.nodes,
    required this.model,
    required this.indexedAt,
  });

  final List<String> folders;
  final List<IndexedNode> nodes;
  final String model;
  final DateTime indexedAt;

  factory KnowledgeIndex.empty() => KnowledgeIndex(
        folders: const [],
        nodes: const [],
        model: '',
        indexedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  IndexedNode? nodeFor(String entryId) {
    for (final n in nodes) {
      if (n.id == entryId) return n;
    }
    return null;
  }

  List<IndexedNode> inFolder(String folder) =>
      nodes.where((n) => n.folder == folder).toList();

  bool get isEmpty => nodes.isEmpty;

  Map<String, Object?> toJson() => {
        'folders': folders,
        'nodes': nodes.map((e) => e.toJson()).toList(),
        'model': model,
        'indexedAt': indexedAt.millisecondsSinceEpoch,
      };

  factory KnowledgeIndex.fromJson(Map<String, Object?> j) => KnowledgeIndex(
        folders: ((j['folders'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        nodes: ((j['nodes'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => IndexedNode.fromJson(e.cast<String, Object?>()))
            .toList(),
        model: (j['model'] as String?) ?? '',
        indexedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['indexedAt'] as int?) ?? 0,
        ),
      );
}
