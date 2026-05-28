import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Organic tree visualisation — drop-in replacement for [PentagonPainter].
///
/// Each axis becomes a **branch** growing upward/outward from a shared
/// trunk. Branch length = axis score (0..100 maps to 0..maxRadius).
/// Leaves (small filled circles) appear along growing branches.
/// Axes at ≥95 % trigger a "bloom" halo on the branch tip.
///
/// Strict black-and-white — the tree uses [fg] / [muted] / [line] colors
/// passed by the caller, no gradients.
class TreePainter extends CustomPainter {
  TreePainter({
    required this.scores,
    required this.fg,
    required this.muted,
    required this.line,
    required this.bg,
    this.progress = 1.0,
    this.highlightedAxisIndex,
    this.bloomedAxes = const <int>{},
    this.bloomPulse = 0.0,
  });

  final List<AxisScore> scores;
  final Color fg;
  final Color muted;
  final Color line;
  final Color bg;
  final double progress;
  final int? highlightedAxisIndex;
  final Set<int> bloomedAxes;
  final double bloomPulse;

  @override
  void paint(Canvas canvas, Size size) {
    final n = scores.length;
    if (n < 3) return;

    final center = Offset(size.width / 2, size.height * 0.85);
    final maxH = size.height * 0.7;
    final trunkH = maxH * 0.25;

    // Trunk — thick line from bottom-center upward.
    final trunkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = fg
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final trunkTop = Offset(center.dx, center.dy - trunkH * progress);
    canvas.drawLine(center, trunkTop, trunkPaint);

    // Small root lines at base.
    final rootPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = muted.withOpacity(0.4)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      center + Offset(-18 * progress, 8 * progress),
      rootPaint,
    );
    canvas.drawLine(
      center,
      center + Offset(18 * progress, 8 * progress),
      rootPaint,
    );

    // Branches — radiate upward from trunkTop.
    final branchMaxLen = maxH * 0.55;
    final rng = math.Random(42); // deterministic "organic" jitter

    for (var i = 0; i < n; i++) {
      final score = scores[i].value.clamp(0.0, 100.0) / 100.0;
      final len = branchMaxLen * score * progress;
      if (len < 2) continue;

      // Fan branches across the top half-circle.
      const angleSpread = math.pi * 0.75;
      const baseAngle = -math.pi / 2; // straight up
      final angle = baseAngle +
          angleSpread * ((i / (n - 1)) - 0.5);

      final highlight = i == highlightedAxisIndex;
      final bloom = bloomedAxes.contains(i);

      // Branch stroke.
      final bw = bloom ? 2.8 : (highlight ? 2.2 : 1.8);
      final branchPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = fg.withOpacity(bloom ? 1.0 : (highlight ? 0.9 : 0.7))
        ..strokeWidth = bw
        ..strokeCap = StrokeCap.round;

      // Bezier control — slight curve for organic feel.
      final jitterX = (rng.nextDouble() - 0.5) * 20;
      final jitterY = (rng.nextDouble() - 0.5) * 12;
      final endX = trunkTop.dx + math.cos(angle) * len;
      final endY = trunkTop.dy + math.sin(angle) * len;
      final end = Offset(endX, endY);
      final ctrl = Offset(
        trunkTop.dx + math.cos(angle) * len * 0.5 + jitterX,
        trunkTop.dy + math.sin(angle) * len * 0.5 + jitterY,
      );

      final path = Path()
        ..moveTo(trunkTop.dx, trunkTop.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      canvas.drawPath(path, branchPaint);

      // Leaves along the branch — more leaves for higher scores.
      final leafCount = (score * 6).round().clamp(0, 6);
      for (var l = 1; l <= leafCount; l++) {
        final t = l / (leafCount + 1);
        // Point on quadratic bezier at parameter t.
        final lx = (1 - t) * (1 - t) * trunkTop.dx +
            2 * (1 - t) * t * ctrl.dx +
            t * t * end.dx;
        final ly = (1 - t) * (1 - t) * trunkTop.dy +
            2 * (1 - t) * t * ctrl.dy +
            t * t * end.dy;
        final leafOffset = Offset(
          lx + (rng.nextDouble() - 0.5) * 8,
          ly + (rng.nextDouble() - 0.5) * 8,
        );
        final leafSize = 2.5 + score * 2.0;
        canvas.drawCircle(
          leafOffset,
          leafSize,
          Paint()
            ..style = PaintingStyle.fill
            ..color = fg.withOpacity(0.15 + score * 0.25),
        );
      }

      // Bloom halo at branch tip.
      if (bloom) {
        final breath = 0.5 + 0.5 * math.sin(bloomPulse * 2 * math.pi);
        canvas.drawCircle(
          end,
          8 + 4 * breath,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = fg.withOpacity(0.3 + 0.3 * breath)
            ..strokeWidth = 1.5,
        );
      }

      // Tip dot.
      canvas.drawCircle(
        end,
        highlight ? 5.0 : 3.5,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fg,
      );

      // Label (axis symbol) near branch tip.
      final labelOffset = Offset(
        end.dx + math.cos(angle) * 16,
        end.dy + math.sin(angle) * 16,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: scores[i].axis.symbol,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        labelOffset - Offset(tp.width / 2, tp.height / 2),
      );
    }
  }

  int? hitTestAxis(Offset tap, Size size, {double tolerance = 28}) {
    final n = scores.length;
    if (n < 3) return null;
    final trunkTop = Offset(
      size.width / 2,
      size.height * 0.85 - size.height * 0.7 * 0.25 * progress,
    );
    final branchMaxLen = size.height * 0.7 * 0.55;

    int? best;
    double bestDist = tolerance;
    for (var i = 0; i < n; i++) {
      final score = scores[i].value.clamp(0.0, 100.0) / 100.0;
      final len = branchMaxLen * score * progress;
      const angleSpread = math.pi * 0.75;
      const baseAngle = -math.pi / 2;
      final angle = baseAngle + angleSpread * ((i / (n - 1)) - 0.5);
      final endX = trunkTop.dx + math.cos(angle) * len;
      final endY = trunkTop.dy + math.sin(angle) * len;
      final d = (Offset(endX, endY) - tap).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(covariant TreePainter oldDelegate) =>
      oldDelegate.scores != scores ||
      oldDelegate.fg != fg ||
      oldDelegate.muted != muted ||
      oldDelegate.line != line ||
      oldDelegate.bg != bg ||
      oldDelegate.progress != progress ||
      oldDelegate.highlightedAxisIndex != highlightedAxisIndex ||
      oldDelegate.bloomedAxes != bloomedAxes ||
      oldDelegate.bloomPulse != bloomPulse;
}
