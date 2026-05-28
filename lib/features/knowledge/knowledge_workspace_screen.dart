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

/// Knowledge workspace with two views: folders + 3D graph.
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
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _showGraph = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
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
          .where(
              (e) => !e.isDeleted && (e.body.isNotEmpty || e.title.isNotEmpty))
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
            'Готово: ${index.folders.length} папок, '
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
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: palette.bg,
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (entries) {
          final activeEntries =
              entries.where((e) => !e.isDeleted).toList(growable: false);
          final index = indexAsync.valueOrNull ?? KnowledgeIndex.empty();
          final linkCount = index.nodes.fold<int>(
              0, (sum, n) => sum + n.relatedIds.length) ~/
              2;

          return Column(
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.hub_outlined, color: palette.fg, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'База знаний',
                        style: TextStyle(
                          color: palette.fg,
                          fontFamily: 'IBMPlexMono',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (index.nodes.isNotEmpty) ...[
                      _StatChip(
                          label: '${index.nodes.length}',
                          icon: Icons.description_outlined,
                          palette: palette),
                      const SizedBox(width: 6),
                      _StatChip(
                          label: '${index.folders.length}',
                          icon: Icons.folder_outlined,
                          palette: palette),
                      const SizedBox(width: 6),
                      _StatChip(
                          label: '$linkCount',
                          icon: Icons.link,
                          palette: palette),
                      const SizedBox(width: 8),
                    ],
                    // Graph/List toggle
                    IconButton(
                      tooltip: _showGraph ? 'Список' : 'Граф',
                      icon: Icon(
                        _showGraph
                            ? Icons.view_list_rounded
                            : Icons.hub_outlined,
                        color: palette.fg,
                      ),
                      onPressed: () =>
                          setState(() => _showGraph = !_showGraph),
                    ),
                    IconButton(
                      tooltip: 'Переиндексировать AI',
                      onPressed: _busy ? null : _reindex,
                      icon: _busy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.fg,
                              ),
                            )
                          : Icon(Icons.auto_awesome, color: palette.fg),
                    ),
                  ],
                ),
              ),

              // ── Search bar (only in list mode) ──
              if (!_showGraph)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(color: palette.fg, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Поиск по заметкам...',
                      hintStyle: TextStyle(color: palette.muted),
                      prefixIcon: Icon(Icons.search, color: palette.muted, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close, color: palette.muted, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: palette.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: palette.fg.withOpacity(0.5)),
                      ),
                    ),
                  ),
                ),

              // ── Folder chips (only in list mode) ──
              if (!_showGraph && index.folders.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _FolderChip(
                          label: 'Все',
                          count: index.nodes.length,
                          isActive: _selectedFolder == null,
                          palette: palette,
                          onTap: () =>
                              setState(() => _selectedFolder = null),
                        ),
                        for (final f in index.folders) ...[
                          const SizedBox(width: 8),
                          _FolderChip(
                            label: f,
                            count: index.nodes
                                .where((n) => n.folder == f)
                                .length,
                            isActive: _selectedFolder == f,
                            palette: palette,
                            onTap: () =>
                                setState(() => _selectedFolder = f),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // ── Body ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _showGraph
                      ? _GraphView(
                          key: const ValueKey('graph'),
                          index: index,
                          entries: activeEntries,
                          palette: palette,
                          onOpenEntry: _openEntry,
                          onReindex: _reindex,
                          busy: _busy,
                        )
                      : _FoldersView(
                          key: const ValueKey('folders'),
                          index: index,
                          entries: activeEntries,
                          palette: palette,
                          selectedFolder: _selectedFolder,
                          query: _query,
                          onOpenEntry: _openEntry,
                          onReindex: _reindex,
                          busy: _busy,
                          isWide: isWide,
                        ),
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
// Stat chip in header
// ---------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.icon,
    required this.palette,
  });
  final String label;
  final IconData icon;
  final NoeticaPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: palette.fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Folder chip
// ---------------------------------------------------------------------------

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.label,
    required this.count,
    required this.isActive,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool isActive;
  final NoeticaPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? palette.fg : palette.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? palette.fg : palette.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isActive ? palette.bg : palette.fg,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: isActive
                      ? palette.bg.withOpacity(0.7)
                      : palette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Folders / list view
// ---------------------------------------------------------------------------

class _FoldersView extends StatelessWidget {
  const _FoldersView({
    super.key,
    required this.index,
    required this.entries,
    required this.palette,
    required this.selectedFolder,
    required this.query,
    required this.onOpenEntry,
    required this.onReindex,
    required this.busy,
    required this.isWide,
  });

  final KnowledgeIndex index;
  final List<Entry> entries;
  final NoeticaPalette palette;
  final String? selectedFolder;
  final String query;
  final ValueChanged<Entry> onOpenEntry;
  final VoidCallback onReindex;
  final bool busy;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyState(
        palette: palette,
        icon: Icons.note_add_outlined,
        title: 'Заметок пока нет',
        subtitle: 'Создай первую заметку или задачу — она появится здесь.',
      );
    }
    if (index.isEmpty) {
      return _EmptyState(
        palette: palette,
        icon: Icons.auto_awesome,
        title: 'AI ещё не разложил по папкам',
        subtitle:
            'Нажми ✨ сверху — нейросеть разложит заметки по '
            'смысловым папкам и найдёт связи.',
        cta: 'Запустить индексацию',
        onCta: busy ? null : onReindex,
      );
    }

    final entryById = {for (final e in entries) e.id: e};

    // Filter by folder
    var visibleNodes = selectedFolder == null
        ? index.nodes
        : index.nodes.where((n) => n.folder == selectedFolder).toList();

    // Filter by search query
    if (query.isNotEmpty) {
      visibleNodes = visibleNodes.where((n) {
        final entry = entryById[n.id];
        if (entry == null) return false;
        return entry.title.toLowerCase().contains(query) ||
            entry.body.toLowerCase().contains(query) ||
            n.summary.toLowerCase().contains(query) ||
            n.tags.any((t) => t.toLowerCase().contains(query));
      }).toList();
    }

    if (visibleNodes.isEmpty) {
      return Center(
        child: Text(
          query.isNotEmpty
              ? 'Ничего не найдено по «$query»'
              : 'Папка пуста',
          style: TextStyle(color: palette.muted, fontSize: 14),
        ),
      );
    }

    // Responsive grid: 1 column on narrow, 2 on wide
    final crossCount = isWide ? 2 : 1;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 140,
      ),
      itemCount: visibleNodes.length,
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
    );
  }
}

// ---------------------------------------------------------------------------
// Note card
// ---------------------------------------------------------------------------

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

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'сегодня';
    if (diff.inDays == 1) return 'вчера';
    if (diff.inDays < 7) return '${diff.inDays} дн. назад';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with type icon + date
              Row(
                children: [
                  Icon(
                    entry.isTask
                        ? (entry.isCompleted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked)
                        : Icons.article_outlined,
                    size: 15,
                    color: entry.isCompleted
                        ? Colors.green.shade400
                        : palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? '(без названия)' : entry.title,
                      style: TextStyle(
                        color: palette.fg,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatDate(entry.updatedAt),
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
                ],
              ),
              // Summary
              if (node.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    node.summary,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              // Tags + links row
              Row(
                children: [
                  if (node.tags.isNotEmpty)
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          for (final t in node.tags.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: palette.fg.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#$t',
                                style: TextStyle(
                                  color: palette.fg.withOpacity(0.7),
                                  fontSize: 10,
                                  fontFamily: 'IBMPlexMono',
                                ),
                              ),
                            ),
                          if (node.tags.length > 3)
                            Text(
                              '+${node.tags.length - 3}',
                              style: TextStyle(
                                  color: palette.muted, fontSize: 10),
                            ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  if (node.relatedIds.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link, size: 12, color: palette.muted),
                        const SizedBox(width: 3),
                        Text(
                          '${node.relatedIds.length}',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Graph view
// ---------------------------------------------------------------------------

class _GraphView extends StatelessWidget {
  const _GraphView({
    super.key,
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
        icon: Icons.hub_outlined,
        title: 'Граф пока пуст',
        subtitle: 'Заведи заметки — узлы появятся здесь.',
      );
    }
    if (index.isEmpty) {
      return _EmptyState(
        palette: palette,
        icon: Icons.auto_awesome,
        title: 'AI ещё не построил связи',
        subtitle:
            'Нажми ✨, чтобы индексатор разложил заметки и нашёл связи.',
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
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.cta,
    this.onCta,
  });
  final NoeticaPalette palette;
  final IconData icon;
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: palette.line),
              ),
              child: Icon(icon, color: palette.fg, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: palette.fg,
                fontFamily: 'IBMPlexMono',
                fontWeight: FontWeight.w700,
                fontSize: 16,
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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(cta!),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.fg,
                  foregroundColor: palette.bg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
