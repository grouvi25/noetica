import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/knowledge_index_models.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';

/// Interactive 3D-projected force-directed graph of indexed knowledge.
///
/// Simulates positions in 3D space (x,y,z), projects to 2D with a simple
/// perspective transform, and lets the user rotate by dragging. Notes
/// are spheres; their colour comes from the folder, size from related-
/// count. Tap a node → open the entry editor sheet.
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
    if (widget.index != oldWidget.index || widget.entries != oldWidget.entries) {
      _buildGraph();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _buildGraph() {
    _nodes.clear();
    _edges.clear();
    final rng = math.Random(42);
    final folderToColor = <String, Color>{};
    final palette = widget.palette;
    final colors = _folderPalette(palette);

    int colorIdx = 0;
    for (final f in widget.index.folders) {
      folderToColor[f] = colors[colorIdx % colors.length];
      colorIdx++;
    }

    final entryById = {for (final e in widget.entries) e.id: e};

    for (final node in widget.index.nodes) {
      final entry = entryById[node.id];
      if (entry == null) continue;
      final color =
          folderToColor[node.folder] ?? palette.fg.withOpacity(0.7);
      _nodes.add(
        _Node3D(
          id: node.id,
          label: entry.title.isEmpty ? '(без названия)' : entry.title,
          folder: node.folder,
          tags: node.tags,
          color: color,
          entry: entry,
          relatedCount: node.relatedIds.length,
          x: (rng.nextDouble() - 0.5) * 6,
          y: (rng.nextDouble() - 0.5) * 6,
          z: (rng.nextDouble() - 0.5) * 6,
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

  List<Color> _folderPalette(NoeticaPalette palette) {
    // Mono-tinted set that works on both light and dark backgrounds.
    return [
      const Color(0xFF7AB8FF),
      const Color(0xFFFFA869),
      const Color(0xFF9CE08C),
      const Color(0xFFFF9CCB),
      const Color(0xFFD4B0FF),
      const Color(0xFFFFD78A),
      const Color(0xFF8DE2D7),
      const Color(0xFFFF8C8C),
    ];
  }

  void _step() {
    if (_nodes.length < 2) return;
    // Lightweight force-directed step: repulsion between all nodes,
    // attraction along edges, mild centering. Tweaked for 60fps with
    // a couple hundred notes.
    final n = _nodes.length;
    for (var i = 0; i < n; i++) {
      final a = _nodes[i];
      a.fx = 0;
      a.fy = 0;
      a.fz = 0;
    }
    // Repulsion.
    for (var i = 0; i < n; i++) {
      final a = _nodes[i];
      for (var j = i + 1; j < n; j++) {
        final b = _nodes[j];
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        var dz = a.z - b.z;
        final d2 = dx * dx + dy * dy + dz * dz + 0.01;
        final inv = 1.0 / d2;
        final f = 1.5 * inv;
        final d = math.sqrt(d2);
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
    // Attraction.
    final nodeById = <String, _Node3D>{for (final n in _nodes) n.id: n};
    for (final e in _edges) {
      final a = nodeById[e.aId];
      final b = nodeById[e.bId];
      if (a == null || b == null) continue;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dz = b.z - a.z;
      final d = math.sqrt(dx * dx + dy * dy + dz * dz) + 0.001;
      final k = e.ghost ? 0.012 : 0.06;
      final f = (d - 2.5) * k;
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
    const damping = 0.82;
    const centering = 0.005;
    for (final node in _nodes) {
      node.fx -= node.x * centering;
      node.fy -= node.y * centering;
      node.fz -= node.z * centering;
      node.vx = (node.vx + node.fx * 0.03) * damping;
      node.vy = (node.vy + node.fy * 0.03) * damping;
      node.vz = (node.vz + node.fz * 0.03) * damping;
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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  setState(() {
                    _yaw += d.delta.dx * 0.005;
                    _pitch -= d.delta.dy * 0.005;
                    _pitch = _pitch.clamp(-math.pi / 2 + 0.1, math.pi / 2 - 0.1);
                  });
                },
                onScaleUpdate: (d) {
                  if (d.scale != 1.0) {
                    setState(() {
                      _zoom = (_zoom * d.scale).clamp(0.4, 4.0);
                    });
                  }
                },
                onTapUp: (d) {
                  final hit = _hitTest(d.localPosition, projected);
                  if (hit != null) widget.onTap(hit.entry);
                },
                onLongPressStart: (d) {
                  final hit = _hitTest(d.localPosition, projected);
                  setState(() => _hoverId = hit?.id);
                },
                onLongPressEnd: (_) => setState(() => _hoverId = null),
                child: CustomPaint(
                  size: size,
                  painter: _GraphPainter(
                    projected: projected,
                    edges: _edges,
                    palette: palette,
                    hoverId: _hoverId,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.fg.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_nodes.length} узлов · ${_edges.where((e) => !e.ghost).length} связей · zoom ${_zoom.toStringAsFixed(1)}x',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontFamily: 'IBMPlexMono',
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.fg.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Тяни — вращай · щипком — масштаб · тап — открыть',
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
      // Yaw (around Y axis): rotate x,z
      var x1 = n.x * cosY + n.z * sinY;
      var z1 = -n.x * sinY + n.z * cosY;
      var y1 = n.y;
      // Pitch (around X axis): rotate y,z
      final y2 = y1 * cosX - z1 * sinX;
      final z2 = y1 * sinX + z1 * cosX;
      // Perspective.
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
    // Painter expects nodes sorted back-to-front.
    result.sort((a, b) => a.depth.compareTo(b.depth));
    return result;
  }

  _Node3D? _hitTest(Offset local, List<_ProjectedNode> projected) {
    // Iterate front-to-back.
    for (var i = projected.length - 1; i >= 0; i--) {
      final p = projected[i];
      final r = (4 + p.node.relatedCount * 1.4) * p.persp;
      final dx = local.dx - p.x;
      final dy = local.dy - p.y;
      if (dx * dx + dy * dy <= r * r) return p.node;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------

class _Node3D {
  _Node3D({
    required this.id,
    required this.label,
    required this.folder,
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
  final List<String> tags;
  final Color color;
  final Entry entry;
  final int relatedCount;
  double x;
  double y;
  double z;
  double vx = 0;
  double vy = 0;
  double vz = 0;
  double fx = 0;
  double fy = 0;
  double fz = 0;
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
  final double x;
  final double y;
  final double depth;
  final double persp;
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.projected,
    required this.edges,
    required this.palette,
    required this.hoverId,
  });

  final List<_ProjectedNode> projected;
  final List<_Edge> edges;
  final NoeticaPalette palette;
  final String? hoverId;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = palette.bg;
    canvas.drawRect(Offset.zero & size, bg);

    final byId = <String, _ProjectedNode>{
      for (final p in projected) p.node.id: p,
    };

    for (final e in edges) {
      final a = byId[e.aId];
      final b = byId[e.bId];
      if (a == null || b == null) continue;
      final paint = Paint()
        ..strokeWidth = e.ghost ? 0.6 : 1.2
        ..color = (e.ghost ? palette.muted : palette.fg)
            .withOpacity(e.ghost ? 0.12 : 0.32);
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    for (final p in projected) {
      final r = (4 + p.node.relatedCount * 1.4) * p.persp;
      final isHover = p.node.id == hoverId;
      final paint = Paint()
        ..color = p.node.color.withOpacity(
          (0.55 + (p.persp - 1.0).clamp(-0.4, 0.7)).clamp(0.2, 1.0),
        );
      canvas.drawCircle(Offset(p.x, p.y), r, paint);
      if (isHover) {
        canvas.drawCircle(
          Offset(p.x, p.y),
          r + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = palette.fg,
        );
      }
      if (p.persp > 0.9 || isHover) {
        textPainter.text = TextSpan(
          text: p.node.label,
          style: TextStyle(
            color: palette.fg.withOpacity(0.85),
            fontSize: 10,
            fontFamily: 'IBMPlexMono',
          ),
        );
        textPainter.layout(maxWidth: 120);
        textPainter.paint(canvas, Offset(p.x + r + 4, p.y - 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}
