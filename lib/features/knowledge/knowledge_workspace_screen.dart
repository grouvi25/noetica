import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/knowledge_index_models.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../services/knowledge_api.dart';
import '../../theme/app_theme.dart';
import '../entry/entry_editor_sheet.dart';
import 'knowledge_graph_3d.dart';

/// Obsidian-style knowledge workspace.
///
/// Two tabs:
///   • «Папки» — AI-grouped notes, click to open the editor sheet.
///   • «Граф» — interactive 3D force-directed view with links.
class KnowledgeWorkspaceScreen extends ConsumerStatefulWidget {
  const KnowledgeWorkspaceScreen({super.key});

  @override
  ConsumerState<KnowledgeWorkspaceScreen> createState() =>
      _KnowledgeWorkspaceScreenState();
}

class _KnowledgeWorkspaceScreenState
    extends ConsumerState<KnowledgeWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _busy = false;
  String? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reindex() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(repositoryProvider.future);
      final entries = await repo.listEntries();
      final filtered = entries
          .where((e) => !e.isDeleted && (e.body.isNotEmpty || e.title.isNotEmpty))
          .toList();
      if (filtered.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Нет заметок для индексации — добавь что-нибудь.'),
          ),
        );
        return;
      }
      final api = ref.read(knowledgeApiProvider);
      final svc = ref.read(knowledgeIndexServiceProvider);
      final index = await api.reindex(filtered);
      await svc.save(index);
      ref.invalidate(knowledgeIndexProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Индекс готов: ${index.folders.length} папок, '
            '${index.nodes.length} заметок.',
          ),
        ),
      );
    } on KnowledgeApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не получилось: ${e.message}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не получилось: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEntry(Entry entry) async {
    await showEntryEditor(context, ref, existing: entry);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final entriesAsync = ref.watch(entriesProvider);
    final indexAsync = ref.watch(knowledgeIndexProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (entries) {
          final activeEntries =
              entries.where((e) => !e.isDeleted).toList(growable: false);
          final index = indexAsync.valueOrNull ?? KnowledgeIndex.empty();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'База знаний',
                        style: TextStyle(
                          color: palette.fg,
                          fontFamily: 'IBMPlexMono',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Переиндексировать через AI',
                      onPressed: _busy ? null : _reindex,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.auto_awesome, color: palette.fg),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment<int>(
                        value: 0,
                        label: const Text('Папки'),
                        icon: const Icon(Icons.folder_outlined, size: 18),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: const Text('Граф'),
                        icon: const Icon(Icons.hub_outlined, size: 18),
                      ),
                    ],
                    selected: {_tab.index},
                    onSelectionChanged: (v) {
                      setState(() => _tab.animateTo(v.first));
                    },
                    style: SegmentedButton.styleFrom(
                      backgroundColor: palette.surface,
                      selectedBackgroundColor: palette.fg.withOpacity(0.12),
                      selectedForegroundColor: palette.fg,
                      foregroundColor: palette.muted,
                      side: BorderSide(color: palette.line),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _FoldersView(
                      index: index,
                      entries: activeEntries,
                      palette: palette,
                      selectedFolder: _selectedFolder,
                      onSelectFolder: (f) =>
                          setState(() => _selectedFolder = f),
                      onOpenEntry: _openEntry,
                      onReindex: _reindex,
                      busy: _busy,
                    ),
                    _GraphView(
                      index: index,
                      entries: activeEntries,
                      palette: palette,
                      onOpenEntry: _openEntry,
                      onReindex: _reindex,
                      busy: _busy,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FoldersView extends StatelessWidget {
  const _FoldersView({
    required this.index,
    required this.entries,
    required this.palette,
    required this.selectedFolder,
    required this.onSelectFolder,
    required this.onOpenEntry,
    required this.onReindex,
    required this.busy,
  });

  final KnowledgeIndex index;
  final List<Entry> entries;
  final NoeticaPalette palette;
  final String? selectedFolder;
  final ValueChanged<String?> onSelectFolder;
  final ValueChanged<Entry> onOpenEntry;
  final VoidCallback onReindex;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyState(
        palette: palette,
        title: 'Заметок пока нет',
        subtitle: 'Создай первую заметку или задачу — она появится в графе.',
      );
    }
    if (index.isEmpty) {
      return _EmptyState(
        palette: palette,
        title: 'AI ещё не разложил по папкам',
        subtitle:
            'Нажми на ✨ сверху — нейросеть разложит твои заметки по '
            'смысловым папкам и предложит связи.',
        cta: 'Запустить индексацию',
        onCta: busy ? null : onReindex,
      );
    }

    final folders = ['Все', ...index.folders];
    final active = selectedFolder ?? 'Все';

    final entryById = {for (final e in entries) e.id: e};
    final visibleNodes = active == 'Все'
        ? index.nodes
        : index.nodes.where((n) => n.folder == active).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 200,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: palette.muted.withOpacity(0.2)),
            ),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: folders.length,
            itemBuilder: (_, i) {
              final f = folders[i];
              final isActive = f == active;
              final count = f == 'Все'
                  ? index.nodes.length
                  : index.nodes.where((n) => n.folder == f).length;
              return InkWell(
                onTap: () => onSelectFolder(f == 'Все' ? null : f),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: isActive
                      ? palette.fg.withOpacity(0.08)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      Icon(
                        f == 'Все' ? Icons.all_inclusive : Icons.folder_outlined,
                        size: 16,
                        color: palette.fg,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(
                            color: palette.fg,
                            fontFamily: 'IBMPlexMono',
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: visibleNodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final n = visibleNodes[i];
              final entry = entryById[n.id];
              if (entry == null) return const SizedBox.shrink();
              return _NoteCard(
                node: n,
                entry: entry,
                palette: palette,
                onOpen: () => onOpenEntry(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.node,
    required this.entry,
    required this.palette,
    required this.onOpen,
  });
  final IndexedNode node;
  final Entry entry;
  final NoeticaPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bg,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: palette.muted.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    entry.isTask ? Icons.check_circle_outline : Icons.notes,
                    size: 16,
                    color: palette.fg,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? '(без названия)' : entry.title,
                      style: TextStyle(
                        color: palette.fg,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'IBMPlexMono',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (node.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  node.summary,
                  style: TextStyle(color: palette.muted, fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (node.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final t in node.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.fg.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#$t',
                          style: TextStyle(
                            color: palette.fg,
                            fontSize: 11,
                            fontFamily: 'IBMPlexMono',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (node.relatedIds.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '↔ связаны: ${node.relatedIds.length}',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontFamily: 'IBMPlexMono',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _GraphView extends StatelessWidget {
  const _GraphView({
    required this.index,
    required this.entries,
    required this.palette,
    required this.onOpenEntry,
    required this.onReindex,
    required this.busy,
  });

  final KnowledgeIndex index;
  final List<Entry> entries;
  final NoeticaPalette palette;
  final ValueChanged<Entry> onOpenEntry;
  final VoidCallback onReindex;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyState(
        palette: palette,
        title: 'Граф пока пуст',
        subtitle: 'Заведи заметки — узлы появятся здесь.',
      );
    }
    if (index.isEmpty) {
      return _EmptyState(
        palette: palette,
        title: 'AI ещё не построил связи',
        subtitle:
            'Нажми ✨, чтобы индексатор разложил заметки и нашёл связи '
            'между ними.',
        cta: 'Построить граф',
        onCta: busy ? null : onReindex,
      );
    }
    return KnowledgeGraph3D(
      index: index,
      entries: entries,
      palette: palette,
      onTap: onOpenEntry,
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.title,
    required this.subtitle,
    this.cta,
    this.onCta,
  });
  final NoeticaPalette palette;
  final String title;
  final String subtitle;
  final String? cta;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, color: palette.fg, size: 36),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: palette.fg,
                fontFamily: 'IBMPlexMono',
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: palette.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (cta != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onCta,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.fg,
                  foregroundColor: palette.bg,
                ),
                child: Text(cta!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
