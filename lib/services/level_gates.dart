import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Features unlocked at specific levels. Gives users a reason to keep
/// growing — each new level opens something new.
enum LevelGate {
  /// L1: Dashboard, Tasks, Рефлексия, Древо (always available).
  dashboard(requiredLevel: 1, label: 'Дашборд'),

  /// L2: AI Coach.
  coach(requiredLevel: 2, label: 'AI-коуч'),

  /// L3: Habits tracker.
  habits(requiredLevel: 3, label: 'Привычки'),

  /// L4: Knowledge graph + notes.
  knowledge(requiredLevel: 4, label: 'База знаний + Граф'),

  /// L5: Advanced analytics.
  analytics(requiredLevel: 5, label: 'Аналитика'),

  /// L6: Data export.
  export(requiredLevel: 6, label: 'Экспорт данных'),

  /// L7+: Custom themes / tree visuals.
  themes(requiredLevel: 7, label: 'Темы и визуал');

  const LevelGate({required this.requiredLevel, required this.label});

  final int requiredLevel;
  final String label;

  bool isUnlocked(int currentLevel) => currentLevel >= requiredLevel;
}

/// A wrapper widget that either shows [child] or a "locked" overlay
/// explaining what level is needed to unlock this feature.
class LevelGateGuard extends StatelessWidget {
  const LevelGateGuard({
    super.key,
    required this.gate,
    required this.currentLevel,
    required this.child,
  });

  final LevelGate gate;
  final int currentLevel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (gate.isUnlocked(currentLevel)) return child;

    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: palette.muted,
            ),
            const SizedBox(height: 16),
            Text(
              gate.label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: palette.fg,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Доступно с уровня ${gate.requiredLevel}',
              style: TextStyle(
                fontSize: 14,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Твой уровень: $currentLevel',
              style: TextStyle(
                fontSize: 14,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: currentLevel / gate.requiredLevel,
              backgroundColor: palette.line,
              valueColor: AlwaysStoppedAnimation(palette.fg),
            ),
            const SizedBox(height: 8),
            Text(
              'Выполняй задачи, чтобы получить XP и открыть новые возможности',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
