import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/knowledge_index_models.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';

/// Obsidian-style 3D force-directed knowledge graph.
///
/// Colored nodes grouped by folder, readable labels, interactive
/// rotation/zoom, tap to open. Designed to be beautiful and functional.
class KnowledgeGraph3D extends StatefulWidget {
  const KnowledgeGraph3D({
    super.key,
    required this.index,
    required this.entries,
    required this.palette,
    required this.onTap,
  });

  final KnowledgeIndex index;
  final List<Entry> entries;
  final NoeticaPalette palette;
  final ValueChanged<Entry> onTap;

  @override
  State<KnowledgeGraph3D> createState() => _KnowledgeGraph3DState();
}

class _KnowledgeGraph3DState extends State<KnowledgeGraph3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final List<_Node3D> _nodes = [];
  final List<_Edge> _edges = [];
  final Map<String, Color> _folderColors = {};
  double _yaw = 0.4;
  double _pitch = -0.25;
  double _zoom = 1.0;
  String? _hoverId;

  @override
  void initState() {
    super.initState();
    _buildGraph();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_step)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant KnowledgeGraph3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index ||
        widget.entries != oldWidget.entries) {
      _buildGraph();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  static const _colorPool = [
    Color(0xFF6C9CFF), // blue
    Color(0xFFFF8C69), // coral
    Color(0xFF7ED891), // green
    Color(0xFFE87FBF), // pink
    Color(0xFFB98EFF), // purple
    Color(0xFFFFCC55), // gold
    Color(0xFF5ECFCF), // teal
    Color(0xFFFF7070), // red
    Color(0xFF8BC4FF), // light blue
    Color(0xFFFFAB5E), // orange
  ];

  void _buildGraph() {
    _nodes.clear();
    _edges.clear();
    _folderColors.clear();
    final rng = math.Random(42);

    int colorIdx = 0;
    for (final f in widget.index.folders) {
      _folderColors[f] = _colorPool[colorIdx % _colorPool.length];
      colorIdx++;
    }

    final entryById = {for (final e in widget.entries) e.id: e};

    for (final node in widget.index.nodes) {
      final entry = entryById[node.id];
      if (entry == null) continue;
      final color = _folderColors[node.folder] ??
          widget.palette.fg.withOpacity(0.7);
      _nodes.add(
        _Node3D(
          id: node.id,
          label: entry.title.isEmpty ? '(без названия)' : entry.title,
          folder: node.folder,
          summary: node.summary,
          tags: node.tags,
          color: color,
          entry: entry,
          relatedCount: node.relatedIds.length,
          x: (rng.nextDouble() - 0.5) * 3,
          y: (rng.nextDouble() - 0.5) * 3,
          z: (rng.nextDouble() - 0.5) * 3,
        ),
      );
    }

    final nodeIds = _nodes.map((n) => n.id).toSet();
    final seenEdges = <String>{};

    for (final node in widget.index.nodes) {
      if (!nodeIds.contains(node.id)) continue;
      for (final r in node.relatedIds) {
        if (!nodeIds.contains(r) || r == node.id) continue;
        final key = (node.id.compareTo(r) < 0)
            ? '${node.id}__$r'
            : '${r}__${node.id}';
        if (seenEdges.contains(key)) continue;
        seenEdges.add(key);
        _edges.add(_Edge(node.id, r));
      }
    }

    // Add folder-group ghost edges for spatial clustering.
    final byFolder = <String, List<String>>{};
    for (final n in _nodes) {
      byFolder.putIfAbsent(n.folder, () => []).add(n.id);
    }
    for (final ids in byFolder.values) {
      for (var i = 0; i < ids.length - 1; i++) {
        final key = (ids[i].compareTo(ids[i + 1]) < 0)
            ? '${ids[i]}__${ids[i + 1]}'
            : '${ids[i + 1]}__${ids[i]}';
        if (seenEdges.contains(key)) continue;
        seenEdges.add(key);
        _edges.add(_Edge(ids[i], ids[i + 1], ghost: true));
      }
    }
  }

  void _step() {
    if (_nodes.length < 2) return;
    final n = _nodes.length;
    for (var i = 0; i < n; i++) {
      _nodes[i].fx = 0;
      _nodes[i].fy = 0;
      _nodes[i].fz = 0;
    }

    // Repulsion — gentle, nodes cluster tightly.
    for (var i = 0; i < n; i++) {
      final a = _nodes[i];
      for (var j = i + 1; j < n; j++) {
        final b = _nodes[j];
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        var dz = a.z - b.z;
        final d2 = dx * dx + dy * dy + dz * dz + 0.01;
        final d = math.sqrt(d2);
        // Same-folder nodes repel less → tighter clusters.
        final repK = (a.folder == b.folder) ? 0.2 : 0.5;
        final f = repK / d2;
        dx /= d;
        dy /= d;
        dz /= d;
        a.fx += dx * f;
        a.fy += dy * f;
        a.fz += dz * f;
        b.fx -= dx * f;
        b.fy -= dy * f;
        b.fz -= dz * f;
      }
    }

    // Attraction along edges.
    final nodeById = <String, _Node3D>{for (final n in _nodes) n.id: n};
    for (final e in _edges) {
      final a = nodeById[e.aId];
      final b = nodeById[e.bId];
      if (a == null || b == null) continue;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dz = b.z - a.z;
      final d = math.sqrt(dx * dx + dy * dy + dz * dz) + 0.001;
      final k = e.ghost ? 0.04 : 0.12;
      final f = (d - 1.2) * k;
      final ux = dx / d;
      final uy = dy / d;
      final uz = dz / d;
      a.fx += ux * f;
      a.fy += uy * f;
      a.fz += uz * f;
      b.fx -= ux * f;
      b.fy -= uy * f;
      b.fz -= uz * f;
    }

    const damping = 0.92;
    const centering = 0.015;
    for (final node in _nodes) {
      node.fx -= node.x * centering;
      node.fy -= node.y * centering;
      node.fz -= node.z * centering;
      node.vx = (node.vx + node.fx * 0.018) * damping;
      node.vy = (node.vy + node.fy * 0.018) * damping;
      node.vz = (node.vz + node.fz * 0.018) * damping;
      const maxV = 0.12;
      node.vx = node.vx.clamp(-maxV, maxV);
      node.vy = node.vy.clamp(-maxV, maxV);
      node.vz = node.vz.clamp(-maxV, maxV);
      node.x += node.vx;
      node.y += node.vy;
      node.z += node.vz;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final projected = _project(size);
        return Stack(
          children: [
            // Main graph canvas
            Positioned.fill(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    setState(() {
                      final delta = event.scrollDelta.dy;
                      _zoom =
                          (_zoom * (1 - delta * 0.001)).clamp(0.3, 5.0);
                    });
                  }
                },
                child: MouseRegion(
                  onHover: (event) {
                    final hit =
                        _hitTest(event.localPosition, projected);
                    final newId = hit?.id;
                    if (newId != _hoverId) {
                      setState(() => _hoverId = newId);
                    }
                  },
                  onExit: (_) {
                    if (_hoverId != null) {
                      setState(() => _hoverId = null);
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) {
                      setState(() {
                        _yaw += d.delta.dx * 0.005;
                        _pitch -= d.delta.dy * 0.005;
                        _pitch = _pitch.clamp(
                            -math.pi / 2 + 0.1, math.pi / 2 - 0.1);
                      });
                    },
                    onScaleUpdate: (d) {
                      if (d.scale != 1.0) {
                        setState(() {
                          _zoom = (_zoom * d.scale).clamp(0.3, 5.0);
                        });
                      }
                    },
                    onTapUp: (d) {
                      final hit =
                          _hitTest(d.localPosition, projected);
                      if (hit != null) widget.onTap(hit.entry);
                    },
                    child: CustomPaint(
                      size: size,
                      painter: _GraphPainter(
                        projected: projected,
                        edges: _edges,
                        palette: palette,
                        hoverId: _hoverId,
                        folderColors: _folderColors,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Folder legend (top-left)
            if (_folderColors.isNotEmpty)
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.bg.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in _folderColors.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: entry.value,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                entry.key,
                                style: TextStyle(
                                  color: palette.fg,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Hover tooltip
            if (_hoverId != null)
              ..._buildTooltip(projected, palette, size),

            // Stats (bottom-right)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.bg.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.line),
                ),
                child: Text(
                  '${_nodes.length} узлов · ${_edges.where((e) => !e.ghost).length} связей',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontFamily: 'IBMPlexMono',
                  ),
                ),
              ),
            ),

            // Controls hint (bottom-left)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.bg.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.line),
                ),
                child: Text(
                  'Тяни — вращай · скролл — масштаб · тап — открыть',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontFamily: 'IBMPlexMono',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildTooltip(
      List<_ProjectedNode> projected, NoeticaPalette palette, Size size) {
    final p = projected.cast<_ProjectedNode?>().firstWhere(
        (p) => p!.node.id == _hoverId,
        orElse: () => null);
    if (p == null) return [];
    final x = p.x.clamp(0, size.width - 200);
    final y = (p.y - 60).clamp(0, size.height - 60);
    return [
      Positioned(
        left: x.toDouble(),
        top: y.toDouble(),
        child: IgnorePointer(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.node.label,
                  style: TextStyle(
                    color: palette.fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: p.node.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p.node.folder,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (p.node.relatedCount > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.link, size: 12, color: palette.muted),
                      const SizedBox(width: 2),
                      Text(
                        '${p.node.relatedCount}',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                if (p.node.summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.node.summary,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (p.node.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final t in p.node.tags.take(3))
                        Text(
                          '#$t',
                          style: TextStyle(
                            color: p.node.color,
                            fontSize: 10,
                            fontFamily: 'IBMPlexMono',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<_ProjectedNode> _project(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = math.min(size.width, size.height) / 6 * _zoom;
    final cosY = math.cos(_yaw);
    final sinY = math.sin(_yaw);
    final cosX = math.cos(_pitch);
    final sinX = math.sin(_pitch);
    final result = <_ProjectedNode>[];
    for (final n in _nodes) {
      var x1 = n.x * cosY + n.z * sinY;
      var z1 = -n.x * sinY + n.z * cosY;
      var y1 = n.y;
      final y2 = y1 * cosX - z1 * sinX;
      final z2 = y1 * sinX + z1 * cosX;
      const camDist = 12.0;
      final pz = camDist - z2;
      final pp = pz <= 0.1 ? 0.1 : pz;
      final persp = camDist / pp;
      final px = cx + x1 * scale * persp;
      final py = cy + y2 * scale * persp;
      result.add(
        _ProjectedNode(
          node: n,
          x: px,
          y: py,
          depth: z2,
          persp: persp,
        ),
      );
    }
    result.sort((a, b) => a.depth.compareTo(b.depth));
    return result;
  }

  _Node3D? _hitTest(Offset local, List<_ProjectedNode> projected) {
    for (var i = projected.length - 1; i >= 0; i--) {
      final p = projected[i];
      final r = _nodeRadius(p);
      final dx = local.dx - p.x;
      final dy = local.dy - p.y;
      if (dx * dx + dy * dy <= (r + 4) * (r + 4)) return p.node;
    }
    return null;
  }

  static double _nodeRadius(_ProjectedNode p) {
    return (5 + p.node.relatedCount * 1.8).clamp(5.0, 20.0) * p.persp;
  }
}

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

class _Node3D {
  _Node3D({
    required this.id,
    required this.label,
    required this.folder,
    required this.summary,
    required this.tags,
    required this.color,
    required this.entry,
    required this.relatedCount,
    required this.x,
    required this.y,
    required this.z,
  });

  final String id;
  final String label;
  final String folder;
  final String summary;
  final List<String> tags;
  final Color color;
  final Entry entry;
  final int relatedCount;
  double x, y, z;
  double vx = 0, vy = 0, vz = 0;
  double fx = 0, fy = 0, fz = 0;
}

class _Edge {
  _Edge(this.aId, this.bId, {this.ghost = false});
  final String aId;
  final String bId;
  final bool ghost;
}

class _ProjectedNode {
  _ProjectedNode({
    required this.node,
    required this.x,
    required this.y,
    required this.depth,
    required this.persp,
  });
  final _Node3D node;
  final double x, y;
  final double depth;
  final double persp;
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.projected,
    required this.edges,
    required this.palette,
    required this.hoverId,
    required this.folderColors,
  });

  final List<_ProjectedNode> projected;
  final List<_Edge> edges;
  final NoeticaPalette palette;
  final String? hoverId;
  final Map<String, Color> folderColors;

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
        Offset.zero & size, Paint()..color = palette.bg);

    final byId = <String, _ProjectedNode>{
      for (final p in projected) p.node.id: p,
    };

    // Draw edges
    for (final e in edges) {
      final a = byId[e.aId];
      final b = byId[e.bId];
      if (a == null || b == null) continue;

      if (e.ghost) {
        canvas.drawLine(
          Offset(a.x, a.y),
          Offset(b.x, b.y),
          Paint()
            ..strokeWidth = 0.5
            ..color = palette.muted.withOpacity(0.08),
        );
      } else {
        // Colored edge: blend the two node colors
        final paint = Paint()
          ..strokeWidth = 1.5
          ..shader = _createEdgeGradient(a, b);
        canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
      }
    }

    // Draw nodes (back to front)
    for (final p in projected) {
      final r = _KnowledgeGraph3DState._nodeRadius(p);
      final isHover = p.node.id == hoverId;
      final alpha =
          (0.6 + (p.persp - 1.0).clamp(-0.3, 0.5)).clamp(0.3, 1.0);

      // Glow behind node
      if (!isHover) {
        canvas.drawCircle(
          Offset(p.x, p.y),
          r + 3,
          Paint()
            ..color = p.node.color.withOpacity(alpha * 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // Node circle
      canvas.drawCircle(
        Offset(p.x, p.y),
        r,
        Paint()..color = p.node.color.withOpacity(alpha),
      );

      // Hover ring
      if (isHover) {
        canvas.drawCircle(
          Offset(p.x, p.y),
          r + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = p.node.color,
        );
        // Larger glow on hover
        canvas.drawCircle(
          Offset(p.x, p.y),
          r + 8,
          Paint()
            ..color = p.node.color.withOpacity(0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      // Labels — show for close-enough nodes or hovered
      if (p.persp > 0.85 || isHover) {
        _drawLabel(canvas, p, r, isHover);
      }
    }
  }

  void _drawLabel(Canvas canvas, _ProjectedNode p, double r, bool isHover) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    // Truncate label for readability
    var label = p.node.label;
    if (label.length > 24) label = '${label.substring(0, 22)}…';

    textPainter.text = TextSpan(
      text: label,
      style: TextStyle(
        color: isHover ? palette.fg : palette.fg.withOpacity(0.8),
        fontSize: isHover ? 12.0 : 10.0,
        fontFamily: 'IBMPlexMono',
        fontWeight: isHover ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    textPainter.layout(maxWidth: 140);

    // Position label below node
    final tx = p.x - textPainter.width / 2;
    final ty = p.y + r + 4;

    // Background pill
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        tx - 4,
        ty - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = palette.bg.withOpacity(isHover ? 0.9 : 0.7),
    );

    textPainter.paint(canvas, Offset(tx, ty));
  }

  Shader _createEdgeGradient(_ProjectedNode a, _ProjectedNode b) {
    return ui.Gradient.linear(
      Offset(a.x, a.y),
      Offset(b.x, b.y),
      [
        a.node.color.withOpacity(0.35),
        b.node.color.withOpacity(0.35),
      ],
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}
