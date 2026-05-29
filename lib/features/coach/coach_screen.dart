import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../data/models.dart';
import '../../data/personal_knowledge_service.dart';
import '../../providers.dart';
import '../../services/coach_api.dart';
import '../../services/level_gates.dart';
import '../../theme/app_theme.dart';
import '../dashboard/widgets/dashboard_stats.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  bool _loading = false;
  MorningPlan? _morning;
  EveningReflection? _evening;
  String? _error;

  // Chat history.
  final List<_ChatMessage> _chatMessages = [];
  final _chatController = TextEditingController();
  bool _chatSending = false;

  bool get _isMorning {
    final hour = DateTime.now().hour;
    return hour < 14;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = ref.read(authServiceProvider);
      final api = CoachApi(auth: authService);
      final profileAsync = ref.read(profileProvider);
      final profile = profileAsync.valueOrNull;
      final entries = ref.read(entriesProvider).valueOrNull ?? [];
      final scores = ref.read(scoresProvider).valueOrNull ?? [];
      final stats = DashboardStats.from(entries);

      // Load personal knowledge for contextual coaching.
      final knowledge = await PersonalKnowledgeService().load();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final activeTasks = entries
          .where((e) =>
              e.kind == EntryKind.task && e.completedAt == null)
          .map((e) => e.title)
          .take(8)
          .toList();

      final completedToday = entries
          .where((e) =>
              e.kind == EntryKind.task &&
              e.completedAt != null &&
              e.completedAt!.isAfter(todayStart))
          .map((e) => e.title)
          .take(10)
          .toList();

      final entriesToday = entries
          .where((e) => e.createdAt.isAfter(todayStart))
          .length;

      final knowledgeCtx = <String, dynamic>{
        'goals': knowledge.goals,
        'summary': knowledge.summary,
        'mood': knowledge.preferences['currentMood'] ?? '',
        'recentReflections': knowledge.recentReflections,
        'completedHighlights': knowledge.completedHighlights,
      };

      if (_isMorning) {
        final plan = await api.generateMorningPlan(
          name: profile?.name ?? '',
          aspiration: profile?.aspiration ?? '',
          axes: scores.map((s) => s.axis.name).toList(),
          activeTasks: activeTasks,
          streak: stats.streak,
          knowledgeContext: knowledgeCtx,
        );
        if (!mounted) return;
        setState(() {
          _morning = plan;
          _loading = false;
        });
      } else {
        final reflection = await api.generateEveningReflection(
          name: profile?.name ?? '',
          completedToday: completedToday,
          remaining: activeTasks.take(5).toList(),
          entriesToday: entriesToday,
          streak: stats.streak,
          knowledgeContext: knowledgeCtx,
        );
        if (!mounted) return;
        setState(() {
          _evening = reflection;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final levelAsync = ref.watch(levelStatsProvider);
    final currentLevel = levelAsync.valueOrNull?.level ?? 1;

    // Level gate check — coach unlocks at L2.
    if (!LevelGate.coach.isUnlocked(currentLevel)) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI-коуч')),
        body: LevelGateGuard(
          gate: LevelGate.coach,
          currentLevel: currentLevel,
          child: const SizedBox.shrink(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMorning ? S.of(context)!.coachMorningTitle : S.of(context)!.coachEveningTitle),
        actions: [
          IconButton(
            tooltip: S.of(context)!.coachRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _generate,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(palette)
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_morning != null) _buildMorningContent(palette),
                          if (_evening != null) _buildEveningContent(palette),
                          // Chat messages.
                          for (final msg in _chatMessages) ...[
                            const SizedBox(height: 12),
                            _buildChatBubble(msg, palette),
                          ],
                          if (_chatSending) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Quick-reply chips + text input.
                    _buildChatInput(palette),
                  ],
                ),
    );
  }

  Widget _buildChatBubble(_ChatMessage msg, NoeticaPalette palette) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? palette.fg.withOpacity(0.1)
              : palette.surface,
          border: isUser ? null : Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Text('🤖 ', style: TextStyle(fontSize: 14, color: palette.muted)),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                msg.text,
                style: TextStyle(
                  color: palette.fg,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInput(NoeticaPalette palette) {
    const chips = [
      'Что мне делать сегодня?',
      'Как улучшить слабую ось?',
      'Мне тяжело мотивироваться',
    ];
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_chatMessages.isEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in chips) ...[
                      ActionChip(
                        label: Text(chip, style: const TextStyle(fontSize: 12)),
                        onPressed: _chatSending ? null : () => _sendChat(chip),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    decoration: InputDecoration(
                      hintText: 'Спросить коуча...',
                      hintStyle: TextStyle(color: palette.muted, fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: palette.line),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(color: palette.fg, fontSize: 14),
                    onSubmitted: _chatSending ? null : _sendChat,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: palette.fg, size: 20),
                  onPressed: _chatSending
                      ? null
                      : () => _sendChat(_chatController.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _chatController.clear();
    setState(() {
      _chatMessages.add(_ChatMessage(text: trimmed, isUser: true));
      _chatSending = true;
    });
    try {
      final authService = ref.read(authServiceProvider);
      final entries = ref.read(entriesProvider).valueOrNull ?? [];
      final scores = ref.read(scoresProvider).valueOrNull ?? [];
      final profile = ref.read(profileProvider).valueOrNull;
      final stats = DashboardStats.from(entries);
      final knowledge = await PersonalKnowledgeService().load();

      final activeTasks = entries
          .where((e) =>
              e.kind == EntryKind.task && e.completedAt == null)
          .map((e) => e.title)
          .take(8)
          .toList();

      final knowledgeCtx = <String, dynamic>{
        'question': trimmed,
        'goals': knowledge.goals,
        'summary': knowledge.summary,
        'mood': knowledge.preferences['currentMood'] ?? '',
        'recentReflections': knowledge.recentReflections,
        'completedHighlights': knowledge.completedHighlights,
      };

      final api = CoachApi(auth: authService);
      final plan = await api.generateMorningPlan(
        name: profile?.name ?? '',
        aspiration: profile?.aspiration ?? '',
        axes: scores.map((s) => s.axis.name).toList(),
        activeTasks: activeTasks,
        streak: stats.streak,
        knowledgeContext: knowledgeCtx,
      );
      final reply = plan.greeting.isNotEmpty
          ? plan.greeting
          : (plan.tasks.isNotEmpty
              ? plan.tasks.map((t) => '• $t').join('\n')
              : 'Нет ответа');
      setState(() {
        _chatMessages.add(_ChatMessage(text: reply, isUser: false));
        _chatSending = false;
      });
    } catch (e) {
      setState(() {
        _chatMessages.add(
          _ChatMessage(text: 'Ошибка: $e', isUser: false),
        );
        _chatSending = false;
      });
    }
  }

  Widget _buildError(NoeticaPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.muted, size: 48),
            const SizedBox(height: 12),
            Text(
              S.of(context)!.coachError,
              style: TextStyle(
                color: palette.fg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(color: palette.muted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _generate,
              child: Text(S.of(context)!.coachRetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMorningContent(NoeticaPalette palette) {
    final plan = _morning!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.greeting,
          style: TextStyle(
            color: palette.fg,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _CoachCard(
          palette: palette,
          icon: Icons.center_focus_strong,
          title: S.of(context)!.coachFocus,
          content: plan.focus,
        ),
        const SizedBox(height: 12),
        _CoachCard(
          palette: palette,
          icon: Icons.checklist,
          title: S.of(context)!.coachPlanToday,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < plan.tasks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.line, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          plan.tasks[i],
                          style: TextStyle(
                            color: palette.fg,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CoachCard(
          palette: palette,
          icon: Icons.local_fire_department,
          title: S.of(context)!.coachMotivation,
          content: plan.motivation,
        ),
      ],
    );
  }

  Widget _buildEveningContent(NoeticaPalette palette) {
    final reflection = _evening!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context)!.coachDayResults,
          style: TextStyle(
            color: palette.fg,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _CoachCard(
          palette: palette,
          icon: Icons.summarize,
          title: S.of(context)!.coachSummary,
          content: reflection.summary,
        ),
        if (reflection.wins.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CoachCard(
            palette: palette,
            icon: Icons.emoji_events,
            title: S.of(context)!.coachWins,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: reflection.wins
                  .map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('+ ', style: TextStyle(
                            color: palette.fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          )),
                          Expanded(
                            child: Text(
                              w,
                              style: TextStyle(
                                color: palette.fg,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (reflection.improvements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CoachCard(
            palette: palette,
            icon: Icons.trending_up,
            title: S.of(context)!.coachImprove,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: reflection.improvements
                  .map(
                    (imp) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('~ ', style: TextStyle(
                            color: palette.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          )),
                          Expanded(
                            child: Text(
                              imp,
                              style: TextStyle(
                                color: palette.fg,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _CoachCard(
          palette: palette,
          icon: Icons.nightlight_round,
          title: S.of(context)!.coachTomorrow,
          content: reflection.encouragement,
        ),
      ],
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.palette,
    required this.icon,
    required this.title,
    this.content,
    this.child,
  });

  final NoeticaPalette palette;
  final IconData icon;
  final String title;
  final String? content;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: palette.fg, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: palette.fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (content != null)
            Text(
              content!,
              style: TextStyle(
                color: palette.fg,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}
