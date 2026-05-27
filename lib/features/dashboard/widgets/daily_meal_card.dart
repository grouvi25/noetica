import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/tools_api.dart';
import '../../../theme/app_theme.dart';

/// "Меню на сегодня" — a tiny Dashboard card that replaces the deleted
/// Ассистент tab's weekly menu generator.
///
/// Philosophy of the v3 redesign: meal planning is a daily concern, not
/// a weekly project. The previous flow asked the user to commit to 21
/// meals + a shopping list — friction that meant the feature got used
/// approximately never. The card here asks for nothing and gives back
/// breakfast / lunch / dinner for *today* in a single tap.
///
/// Storage: shared_preferences keyed by `daily_meal_${YYYY-MM-DD}` so
/// the same plan persists across app restarts within the day and is
/// automatically forgotten tomorrow (no manual cleanup).
class DailyMealCard extends ConsumerStatefulWidget {
  const DailyMealCard({super.key, required this.palette});

  final NoeticaPalette palette;

  @override
  ConsumerState<DailyMealCard> createState() => _DailyMealCardState();
}

class _DailyMealCardState extends ConsumerState<DailyMealCard> {
  bool _loading = false;
  String? _error;
  _StoredMeal? _meal;
  bool _hydrated = false;

  String get _todayKey {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return 'daily_meal_$y-$m-$d';
  }

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_todayKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, Object?>;
        _meal = _StoredMeal.fromJson(json);
      }
    } catch (_) {
      // Corrupt cache — silently ignore; user can regenerate.
    } finally {
      if (mounted) setState(() => _hydrated = true);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ToolsApi();
      final plan = await api.generateMenu(
        goal: MenuGoal.classic,
        servings: 1,
        durationDays: 1,
      );
      if (plan.days.isEmpty) {
        throw Exception('пустое меню');
      }
      final day = plan.days.first;
      final stored = _StoredMeal(
        breakfast: _MealLine.from(day.breakfast),
        lunch: _MealLine.from(day.lunch),
        dinner: _MealLine.from(day.dinner),
        snack: _MealLine.from(day.snack),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_todayKey, jsonEncode(stored.toJson()));
      if (!mounted) return;
      setState(() => _meal = stored);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'не получилось — попробуй ещё раз');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_todayKey);
    if (!mounted) return;
    setState(() => _meal = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    if (!_hydrated) {
      return _shell(
        palette,
        child: const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (_meal == null) {
      return _shell(
        palette,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Что съесть сегодня?',
              style: TextStyle(
                color: palette.fg,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Завтрак, обед и ужин одним нажатием.',
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restaurant_menu_outlined, size: 18),
                  label: Text(_loading ? 'Готовлю…' : 'Сгенерировать'),
                ),
                if (_error != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    final m = _meal!;
    return _shell(
      palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Меню на сегодня',
                  style: TextStyle(
                    color: palette.fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Перегенерить',
                onPressed: _loading ? null : _generate,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
              ),
              IconButton(
                tooltip: 'Очистить',
                onPressed: _loading ? null : _clear,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (m.breakfast != null)
            _row(palette, 'Завтрак', m.breakfast!),
          if (m.lunch != null) _row(palette, 'Обед', m.lunch!),
          if (m.dinner != null) _row(palette, 'Ужин', m.dinner!),
          if (m.snack != null) _row(palette, 'Перекус', m.snack!),
        ],
      ),
    );
  }

  Widget _row(NoeticaPalette palette, String label, _MealLine meal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: palette.muted,
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.name,
                  style: TextStyle(color: palette.fg, fontSize: 14),
                ),
                if (meal.calories > 0)
                  Text(
                    '~${meal.calories} ккал',
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell(NoeticaPalette palette, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _StoredMeal {
  _StoredMeal({this.breakfast, this.lunch, this.dinner, this.snack});

  final _MealLine? breakfast;
  final _MealLine? lunch;
  final _MealLine? dinner;
  final _MealLine? snack;

  Map<String, Object?> toJson() => {
        if (breakfast != null) 'breakfast': breakfast!.toJson(),
        if (lunch != null) 'lunch': lunch!.toJson(),
        if (dinner != null) 'dinner': dinner!.toJson(),
        if (snack != null) 'snack': snack!.toJson(),
      };

  static _StoredMeal fromJson(Map<String, Object?> json) {
    return _StoredMeal(
      breakfast: _MealLine.maybeFromJson(json['breakfast']),
      lunch: _MealLine.maybeFromJson(json['lunch']),
      dinner: _MealLine.maybeFromJson(json['dinner']),
      snack: _MealLine.maybeFromJson(json['snack']),
    );
  }
}

class _MealLine {
  _MealLine({required this.name, required this.calories});

  final String name;
  final int calories;

  Map<String, Object?> toJson() => {'name': name, 'calories': calories};

  static _MealLine? from(MenuMeal? meal) {
    if (meal == null) return null;
    return _MealLine(name: meal.name, calories: meal.calories);
  }

  static _MealLine? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final cal = (raw['calories'] as num?)?.toInt() ?? 0;
    return _MealLine(name: name, calories: cal);
  }
}
