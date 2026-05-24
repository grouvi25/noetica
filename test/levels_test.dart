import 'package:flutter_test/flutter_test.dart';
import 'package:noetica/services/levels.dart';

void main() {
  test('escalating thresholds: 0 → L1, 100 → L2, 250 → L3, 450 → L4, '
      '700 → L5, 1000 → L6', () {
    expect(levelStatsFor(0).level, 1);
    expect(levelStatsFor(99).level, 1);
    expect(levelStatsFor(100).level, 2);
    expect(levelStatsFor(249).level, 2);
    expect(levelStatsFor(250).level, 3);
    expect(levelStatsFor(449).level, 3);
    expect(levelStatsFor(450).level, 4);
    expect(levelStatsFor(699).level, 4);
    expect(levelStatsFor(700).level, 5);
    expect(levelStatsFor(999).level, 5);
    expect(levelStatsFor(1000).level, 6);
  });

  test('progress is 0..1 within current level', () {
    final s = levelStatsFor(150);
    expect(s.level, 2);
    expect(s.xpAtLevelStart, 100);
    expect(s.xpAtNextLevel, 250);
    expect(s.xpIntoLevel, 50);
    expect(s.xpForLevel, 150);
    expect(s.progress, closeTo(50 / 150, 1e-9));
  });

  test('post-fixed-table levels keep advancing with 50 + level*50 spans', () {
    // L6 starts at 1000, span = 50 + 6*50 = 350 → ends 1350.
    final s6 = levelStatsFor(1000);
    expect(s6.level, 6);
    expect(s6.xpAtLevelStart, 1000);
    expect(s6.xpAtNextLevel, 1350);

    // L7 starts at 1350, span = 50 + 7*50 = 400 → ends 1750.
    final s7 = levelStatsFor(1350);
    expect(s7.level, 7);
    expect(s7.xpAtLevelStart, 1350);
    expect(s7.xpAtNextLevel, 1750);

    // L8 starts at 1750, span = 50 + 8*50 = 450 → ends 2200.
    final s8 = levelStatsFor(1750);
    expect(s8.level, 8);
    expect(s8.xpAtLevelStart, 1750);
    expect(s8.xpAtNextLevel, 2200);
  });

  test('clamps negative input', () {
    expect(levelStatsFor(-50).level, 1);
    expect(levelStatsFor(-50).totalXp, 0);
  });

  group('эпохи (v3 — derived from axis level)', () {
    test('Lv 1-5 → Э1, Lv 6-10 → Э2, Lv 11-15 → Э3', () {
      expect(epochForLevel(1), 1);
      expect(epochForLevel(5), 1);
      expect(epochForLevel(6), 2);
      expect(epochForLevel(10), 2);
      expect(epochForLevel(11), 3);
      expect(epochForLevel(15), 3);
      expect(epochForLevel(16), 4);
    });

    test('clamps non-positive level to Э1', () {
      expect(epochForLevel(0), 1);
      expect(epochForLevel(-3), 1);
    });

    test('axisEpochName returns growth-themed labels', () {
      expect(axisEpochName(1), 'Зерно');
      expect(axisEpochName(2), 'Росток');
      expect(axisEpochName(3), 'Побег');
      expect(axisEpochName(4), 'Ветвь');
      expect(axisEpochName(5), 'Крона');
      expect(axisEpochName(6), 'Древо');
      expect(axisEpochName(7), 'Роща');
      // Anything beyond the named set falls back to "Лес".
      expect(axisEpochName(99), 'Лес');
    });
  });

  group('глобальные звания', () {
    test('rank tiers grow with level', () {
      expect(globalRankName(1), 'Новичок');
      expect(globalRankName(4), 'Новичок');
      expect(globalRankName(5), 'Странник');
      expect(globalRankName(9), 'Странник');
      expect(globalRankName(10), 'Искатель');
      expect(globalRankName(14), 'Искатель');
      expect(globalRankName(15), 'Практик');
      expect(globalRankName(20), 'Мастер');
      expect(globalRankName(30), 'Архитектор');
      expect(globalRankName(50), 'Хранитель');
      expect(globalRankName(100), 'Хранитель');
    });
  });

  group('xpToNextLevel', () {
    test('reports remaining XP within current level', () {
      // 150 → Lv 2 [100..250], next is 250, so 100 remaining.
      expect(xpToNextLevel(levelStatsFor(150)), 100);
      // Right at level start → full span remaining.
      expect(xpToNextLevel(levelStatsFor(100)), 150); // span L2 = 250-100
      // Right at next-level threshold → 0 remaining (just rolled over).
      expect(xpToNextLevel(levelStatsFor(249)), 1);
    });
  });
}
