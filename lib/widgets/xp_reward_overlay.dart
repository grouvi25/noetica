import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Overlay shown when a task is completed — XP floats up and confetti
/// particles burst outward. Provides the dopamine hit the audit found
/// missing from the current flow.
class XpRewardOverlay extends StatefulWidget {
  const XpRewardOverlay({
    super.key,
    required this.xp,
    this.levelUp,
    this.levelName,
    this.onDone,
  });

  final int xp;

  /// If non-null, a level-up banner is shown after the XP animation.
  final int? levelUp;
  final String? levelName;
  final VoidCallback? onDone;

  /// Show the overlay as a top-level route overlay entry.
  static void show(
    BuildContext context, {
    required int xp,
    int? levelUp,
    String? levelName,
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => XpRewardOverlay(
        xp: xp,
        levelUp: levelUp,
        levelName: levelName,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<XpRewardOverlay> createState() => _XpRewardOverlayState();
}

class _XpRewardOverlayState extends State<XpRewardOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _xpCtrl;
  late final AnimationController _confettiCtrl;
  late final AnimationController _levelCtrl;
  late final List<_Particle> _particles;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();

    _xpCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _levelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _particles = List.generate(15, (_) => _Particle(_rng));

    _xpCtrl.forward();
    _confettiCtrl.forward();

    if (widget.levelUp != null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _levelCtrl.forward();
      });
    }

    final totalMs = widget.levelUp != null ? 2200 : 1200;
    Future.delayed(Duration(milliseconds: totalMs), () {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _xpCtrl.dispose();
    _confettiCtrl.dispose();
    _levelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Confetti particles
            AnimatedBuilder(
              animation: _confettiCtrl,
              builder: (_, __) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _ConfettiPainter(
                    particles: _particles,
                    progress: _confettiCtrl.value,
                    fg: palette.fg,
                  ),
                );
              },
            ),
            // XP text floating up
            Center(
              child: AnimatedBuilder(
                animation: _xpCtrl,
                builder: (_, __) {
                  final t = _xpCtrl.value;
                  final opacity = t < 0.7 ? 1.0 : (1.0 - (t - 0.7) / 0.3);
                  final yOffset = -80 * t;
                  final scale = 1.0 + 0.3 * Curves.elasticOut.transform(
                    (t * 2).clamp(0.0, 1.0),
                  );
                  return Transform.translate(
                    offset: Offset(0, yOffset),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: Text(
                          '+${widget.xp} XP',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: palette.fg,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Level-up banner
            if (widget.levelUp != null)
              Center(
                child: AnimatedBuilder(
                  animation: _levelCtrl,
                  builder: (_, __) {
                    final t = _levelCtrl.value;
                    final scale = Curves.elasticOut.transform(t);
                    final opacity = t.clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: palette.fg, width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '🎉',
                                style: TextStyle(fontSize: 32),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Уровень ${widget.levelUp}',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: palette.fg,
                                ),
                              ),
                              if (widget.levelName != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.levelName!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: palette.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Particle {
  _Particle(math.Random rng)
      : angle = rng.nextDouble() * 2 * math.pi,
        speed = 120 + rng.nextDouble() * 200,
        size = 3 + rng.nextDouble() * 4,
        rotationSpeed = rng.nextDouble() * 4 - 2;

  final double angle;
  final double speed;
  final double size;
  final double rotationSpeed;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.particles,
    required this.progress,
    required this.fg,
  });

  final List<_Particle> particles;
  final double progress;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final gravity = 200 * progress * progress;

    for (final p in particles) {
      final t = progress;
      final dx = math.cos(p.angle) * p.speed * t;
      final dy = math.sin(p.angle) * p.speed * t + gravity;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = fg.withOpacity(opacity * 0.7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        center + Offset(dx, dy),
        p.size * (1.0 - progress * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress;
}
