import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';

// Organic tree colours.
const _kTrunk = Color(0xFF8B6914);
const _kBranchLow = Color(0xFF6B8E23);
const _kBranchHigh = Color(0xFF32CD32);
const _kLeaf = Color(0xFF228B22);
const _kBloom = Color(0xFFFF69B4);

/// Organic tree + pentagram visualisation.
///
/// Each axis becomes a **branch** growing upward from a shared trunk.
/// Branch colour shifts from olive to bright green with score.
/// Pentagram connecting lines appear between tips when score > 30 %.
/// Axes at ≥ 95 % bloom with pink petals.
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

    // Total XP drives trunk thickness (1..4 px).
    final totalScore = scores.fold<double>(0, (s, a) => s + a.value) / n;
    final trunkW = 1.5 + (totalScore / 100) * 2.5;

    // Trunk.
    final trunkTop = Offset(center.dx, center.dy - trunkH * progress);
    final trunkPath = Path()
      ..moveTo(center.dx, center.dy)
      ..quadraticBezierTo(
        center.dx - 3,
        center.dy - trunkH * 0.5 * progress,
        trunkTop.dx,
        trunkTop.dy,
      );
    canvas.drawPath(
      trunkPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _kTrunk
        ..strokeWidth = trunkW
        ..strokeCap = StrokeCap.round,
    );

    // Roots.
    final rootPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = _kTrunk.withOpacity(0.4)
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
    canvas.drawLine(
      center,
      center + Offset(-8 * progress, 12 * progress),
      rootPaint,
    );

    // Branches.
    final branchMaxLen = maxH * 0.55;
    final rng = math.Random(42);
    final tips = <Offset>[];
    final tipScores = <double>[];

    for (var i = 0; i < n; i++) {
      final score = scores[i].value.clamp(0.0, 100.0) / 100.0;
      final len = branchMaxLen * score * progress;

      const angleSpread = math.pi * 0.75;
      const baseAngle = -math.pi / 2;
      final angle = baseAngle + angleSpread * ((i / (n - 1)) - 0.5);

      final endX = trunkTop.dx + math.cos(angle) * len;
      final endY = trunkTop.dy + math.sin(angle) * len;
      final end = len < 2 ? trunkTop : Offset(endX, endY);
      tips.add(end);
      tipScores.add(score);

      if (len < 2) continue;

      final highlight = i == highlightedAxisIndex;
      final bloom = bloomedAxes.contains(i);

      // Branch colour: olive → bright green with score.
      final branchColor = Color.lerp(_kBranchLow, _kBranchHigh, score)!;
      final bw = bloom ? 2.8 : (highlight ? 2.2 : (1.0 + score));

      final jitterX = (rng.nextDouble() - 0.5) * 20;
      final jitterY = (rng.nextDouble() - 0.5) * 12;
      final ctrl = Offset(
        trunkTop.dx + math.cos(angle) * len * 0.5 + jitterX,
        trunkTop.dy + math.sin(angle) * len * 0.5 + jitterY,
      );

      final path = Path()
        ..moveTo(trunkTop.dx, trunkTop.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = branchColor
          ..strokeWidth = bw
          ..strokeCap = StrokeCap.round,
      );

      // Leaves along the branch.
      final leafCount = (score * 6).round().clamp(0, 6);
      for (var l = 1; l <= leafCount; l++) {
        final t = l / (leafCount + 1);
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
            ..color = _kLeaf.withOpacity(0.25 + score * 0.35),
        );
      }

      // Bloom petals at branch tip.
      if (bloom) {
        final breath = 0.5 + 0.5 * math.sin(bloomPulse * 2 * math.pi);
        for (var p = 0; p < 4; p++) {
          final petalAngle = angle + (p - 1.5) * 0.4;
          final petalR = 5.0 + 3.0 * breath;
          canvas.drawCircle(
            Offset(
              end.dx + math.cos(petalAngle) * petalR,
              end.dy + math.sin(petalAngle) * petalR,
            ),
            3.0 + breath,
            Paint()
              ..style = PaintingStyle.fill
              ..color = _kBloom.withOpacity(0.5 + 0.3 * breath),
          );
        }
      }

      // Tip dot.
      canvas.drawCircle(
        end,
        highlight ? 5.0 : 3.5,
        Paint()
          ..style = PaintingStyle.fill
          ..color = branchColor,
      );

      // Label.
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

    // Pentagon connecting lines between branch tips (visible when score > 30%).
    if (tips.length >= 3) {
      for (var i = 0; i < tips.length; i++) {
        final j = (i + 1) % tips.length;
        final avgScore = (tipScores[i] + tipScores[j]) / 2;
        if (avgScore < 0.3) continue;
        canvas.drawLine(
          tips[i],
          tips[j],
          Paint()
            ..style = PaintingStyle.stroke
            ..color = fg.withOpacity(avgScore * 0.3)
            ..strokeWidth = 1.0,
        );
      }

      // Semi-transparent polygon fill.
      final fillPath = Path()..moveTo(tips[0].dx, tips[0].dy);
      for (var i = 1; i < tips.length; i++) {
        fillPath.lineTo(tips[i].dx, tips[i].dy);
      }
      fillPath.close();
      final avgAll = tipScores.fold<double>(0, (s, v) => s + v) / tipScores.length;
      if (avgAll > 0.2) {
        canvas.drawPath(
          fillPath,
          Paint()
            ..style = PaintingStyle.fill
            ..color = _kBranchHigh.withOpacity(avgAll * 0.12),
        );
      }
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
