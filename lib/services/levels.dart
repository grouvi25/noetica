import 'package:flutter/foundation.dart';

/// Lifetime level math. Pure: no I/O, no DB.
///
/// Lifetime XP is the sum of `xp` over all completed tasks (no decay window;
/// the pentagon already shows the 30-day decay, but the user level should be
/// permanent reward — completing things should always feel like "you grew",
/// not "you grew briefly and then lost it").
///
/// Thresholds (cumulative XP needed to *enter* a level):
///   L1 =    0
///   L2 =  100
///   L3 =  250
///   L4 =  450
///   L5 =  700
///   L6 = 1000
///   L7+: span(level) = 50 + level × 50.
/// So the curve gets steadily harder as the user climbs (no plateau), but
/// the early ramps are softer than v1 — getting to L4 is now reachable in
/// a few good weeks instead of a couple of months. Matches the
/// "возрастающие пороги" answer in docs/redesign-v2.md.
@immutable
class LevelStats {
  const LevelStats({
    required this.totalXp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForLevel,
    required this.xpAtLevelStart,
    required this.xpAtNextLevel,
  });

  final int totalXp;
  final int level;

  /// Progress from this level's start toward the next level (0..xpForLevel).
  final int xpIntoLevel;

  /// XP needed to span from this level's start to the next.
  final int xpForLevel;

  final int xpAtLevelStart;
  final int xpAtNextLevel;

  /// 0..1 progress to next level.
  double get progress => xpForLevel == 0 ? 1.0 : xpIntoLevel / xpForLevel;
}

/// Cumulative XP at the *start* of each level, L1..L6.
/// L6 onwards uses [_spanForLevel].
const List<int> _kFixedStarts = [0, 100, 250, 450, 700, 1000];

/// Span needed to cross from level [n] to level [n+1].
/// For L1..L5 the span is read from [_kFixedStarts]; for L≥6 we use the
/// "50 + level*50" growth curve.
int _spanForLevel(int level) {
  // L≥6: L6 → 350, L7 → 400, L8 → 450, ...
  return 50 + level * 50;
}

/// How much XP one needs to accumulate on a single axis to advance its
/// "эпоха" — a purely additive, permanent progression indicator that
/// sits alongside the level system. Whereas `level` is a global stat
/// based on lifetime XP, epoch is per-axis and tied to task output
/// rather than the 30-day decay curve shown on the pentagon.
/// Each epoch buys a visual upgrade (extra halo ring on the axis
/// branch) without resetting anything, which is what makes filling
/// the pentagon to 100 % still meaningful — you're now working toward
/// the next эпоха on each axis.
///
/// **Deprecated in v3** — epochs are now derived from axis level
/// directly (one эпоха per 5 levels), not from a parallel XP counter.
/// Use [epochForLevel] / [axisEpochName] instead. Kept for backward
/// compatibility while call sites migrate.
@Deprecated('Use epochForLevel(axisLevel) instead — single source of truth.')
const int kXpPerEpoch = 500;

/// Compute an axis' эпоха from its cumulative task XP. Starts at 1 so
/// a brand-new axis reads "эпоха 1" (not 0).
///
/// **Deprecated in v3** — see [kXpPerEpoch] note. Use [epochForLevel].
@Deprecated('Use epochForLevel(axisLevel) instead — single source of truth.')
int epochFromXp(int axisTotalXp) {
  if (axisTotalXp <= 0) return 1;
  return 1 + (axisTotalXp ~/ kXpPerEpoch);
}

/// XP still required to push the axis into its next эпоха.
///
/// **Deprecated in v3** — эпоха is now tied to axis level, so the
/// "до следующей эпохи" stat is replaced by "до следующего уровня".
@Deprecated('Use xpToNextLevel(LevelStats) instead — эпоха is now level-derived.')
int xpToNextEpoch(int axisTotalXp) {
  final e = epochFromXp(axisTotalXp);
  final cap = e * kXpPerEpoch;
  final remaining = cap - axisTotalXp;
  return remaining < 0 ? 0 : remaining;
}

// === v3 progression model ===
//
// One source of truth: lifetime XP → axis level (via [levelStatsFor]).
// Эпоха is a *visual milestone* on top of axis level: every 5 levels
// you cross into a new epoch with a new name and visual treatment.
// This collapses the previous twin counters (level + standalone epoch)
// into one continuous track that's easier for the user to read.

/// How many axis levels are in one эпоха. 5 means: Lv 1-5 = Э1,
/// Lv 6-10 = Э2, etc.
const int kLevelsPerEpoch = 5;

/// Compute эпоха from axis level. Starts at 1 (Lv 1-5 = Э1).
int epochForLevel(int axisLevel) {
  if (axisLevel <= 0) return 1;
  return 1 + ((axisLevel - 1) ~/ kLevelsPerEpoch);
}

/// XP still required to push the axis into its next level. Drives the
/// progress bar shown on the axis detail sheet.
int xpToNextLevel(LevelStats ls) {
  final remaining = ls.xpAtNextLevel - ls.totalXp;
  return remaining < 0 ? 0 : remaining;
}

/// Звание ("rank name") for a global user level. The user climbs through
/// these tiers as they accumulate lifetime XP across all axes — a
/// cosmetic reward that makes "Lv 7" mean something more than a number.
String globalRankName(int level) {
  if (level <= 0) return 'Новичок';
  if (level < 5) return 'Новичок';
  if (level < 10) return 'Странник';
  if (level < 15) return 'Искатель';
  if (level < 20) return 'Практик';
  if (level < 30) return 'Мастер';
  if (level < 50) return 'Архитектор';
  return 'Хранитель';
}

/// Звание per-axis-epoch — the symbolic name of the эпоха you're
/// currently in on a single axis. Same idea as [globalRankName] but
/// per-axis, themed around growth ("Зерно → Росток → … → Лес").
String axisEpochName(int epoch) {
  switch (epoch) {
    case 1:
      return 'Зерно';
    case 2:
      return 'Росток';
    case 3:
      return 'Побег';
    case 4:
      return 'Ветвь';
    case 5:
      return 'Крона';
    case 6:
      return 'Древо';
    case 7:
      return 'Роща';
    default:
      return 'Лес';
  }
}

LevelStats levelStatsFor(int totalXp) {
  if (totalXp < 0) totalXp = 0;

  // Levels 1..4 read straight from the fixed table.
  for (var i = 0; i < _kFixedStarts.length - 1; i++) {
    final start = _kFixedStarts[i];
    final next = _kFixedStarts[i + 1];
    if (totalXp < next) {
      return LevelStats(
        totalXp: totalXp,
        level: i + 1,
        xpIntoLevel: totalXp - start,
        xpForLevel: next - start,
        xpAtLevelStart: start,
        xpAtNextLevel: next,
      );
    }
  }

  // L6 and beyond: span = 50 + level * 50.
  var level = _kFixedStarts.length; // 6
  var start = _kFixedStarts.last; // 1000
  while (true) {
    final span = _spanForLevel(level);
    final next = start + span;
    if (totalXp < next) {
      return LevelStats(
        totalXp: totalXp,
        level: level,
        xpIntoLevel: totalXp - start,
        xpForLevel: span,
        xpAtLevelStart: start,
        xpAtNextLevel: next,
      );
    }
    start = next;
    level += 1;
  }
}
