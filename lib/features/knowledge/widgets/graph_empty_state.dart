import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../graph_models.dart';

/// Empty state shown when the graph has no nodes matching
/// the current filter.
class GraphEmptyState extends StatelessWidget {
  const GraphEmptyState({
    super.key,
    required this.filter,
    required this.palette,
    required this.onCreateEntry,
    required this.onResetFilter,
  });

  final GraphFilterMode filter;
  final NoeticaPalette palette;
  final VoidCallback onCreateEntry;
  final VoidCallback onResetFilter;

  @override
  Widget build(BuildContext context) {
    final (title, hint, primaryLabel, primaryAction, showReset) =
        _copyForFilter();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filter.icon, size: 48, color: palette.muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.fg,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.muted),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (primaryAction != null)
                  FilledButton.icon(
                    onPressed: primaryAction,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(primaryLabel),
                  ),
                if (showReset)
                  OutlinedButton.icon(
                    onPressed: onResetFilter,
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Сбросить фильтр'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, String, String, VoidCallback?, bool) _copyForFilter() {
    switch (filter) {
      case GraphFilterMode.all:
        return (
          'База знаний пока пуста',
          'Создайте первую заметку или задачу — они появятся здесь как узлы графа.',
          'Создать запись',
          onCreateEntry,
          false,
        );
      case GraphFilterMode.notes:
        return (
          'Заметок пока нет',
          'Заметки будут видны как отдельные узлы. Связи появляются автоматически, когда в теле есть [[ссылка]] на другую заметку.',
          'Создать заметку',
          onCreateEntry,
          true,
        );
      case GraphFilterMode.tasks:
        return (
          'Задач в графе нет',
          'Создайте задачу через «+» или сгенерируйте план задач из вашей цели.',
          'Создать запись',
          onCreateEntry,
          true,
        );
      case GraphFilterMode.bookmarks:
        return (
          'Закладок пока нет',
          'Долгое нажатие на узел графа добавит его в закладки.',
          '',
          null,
          true,
        );
      case GraphFilterMode.daily:
        return (
          'Дневник пуст',
          'Тапните иконку календаря в шапке, чтобы создать запись на сегодня.',
          '',
          null,
          true,
        );
      case GraphFilterMode.knowledge:
        return (
          'Знания о себе пусты',
          'Заполните цели, ограничения и достижения через тапы по веткам графа — это даст AI больше контекста для генерации планов.',
          '',
          null,
          true,
        );
    }
  }
}
