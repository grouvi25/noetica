import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/personal_knowledge_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/xp_reward_overlay.dart';

const _kMoodKey = 'noetica.mood.today';
const _kMoodDateKey = 'noetica.mood.date';

const List<String> kMoodEmojis = ['😊', '😐', '😔', '🔥', '😴'];
const List<String> kMoodLabels = [
  'Хорошо',
  'Нормально',
  'Тяжело',
  'В огне',
  'Устал',
];

/// Mood check-in strip — 5 emoji buttons, one tap, +5 XP context for AI.
class MoodPicker extends StatefulWidget {
  const MoodPicker({super.key, required this.palette});

  final NoeticaPalette palette;

  @override
  State<MoodPicker> createState() => _MoodPickerState();
}

class _MoodPickerState extends State<MoodPicker> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_kMoodDateKey);
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    if (savedDate == todayStr) {
      final idx = prefs.getInt(_kMoodKey);
      if (mounted && idx != null) setState(() => _selected = idx);
    }
  }

  Future<void> _pick(int index) async {
    final wasFirst = _selected == null;
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    await prefs.setInt(_kMoodKey, index);
    await prefs.setString(_kMoodDateKey, todayStr);
    await PersonalKnowledgeService().recordMood(
      mood: kMoodLabels[index],
      emoji: kMoodEmojis[index],
    );
    // +5 XP for daily mood check-in (first pick today only).
    if (wasFirst && mounted) {
      XpRewardOverlay.show(context, xp: 5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Как ты сегодня?',
            style: TextStyle(
              color: p.fg,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < kMoodEmojis.length; i++)
                _MoodButton(
                  emoji: kMoodEmojis[i],
                  label: kMoodLabels[i],
                  selected: _selected == i,
                  palette: p,
                  onTap: () => _pick(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  const _MoodButton({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final NoeticaPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? palette.fg.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? palette.fg : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? palette.fg : palette.muted,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
