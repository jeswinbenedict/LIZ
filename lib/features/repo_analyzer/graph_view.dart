import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'repo_models.dart';

/// An architecture diagram from the analysis (repo_models.dart, ArchGraph),
/// drawn in layers: each node one column to the right of what points at it,
/// so a system reads left to right from the person to the data. Nodes with no
/// links fill a grid after them. Pan and pinch to move around; tap a node to
/// select it (the page shows what it is and where it was found).
class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.graph,
    required this.selected,
    required this.onSelect,
    this.height = 460,
  });

  final ArchGraph graph;
  final String? selected;
  final ValueChanged<GraphNode> onSelect;
  final double height;

  @override
  State<GraphView> createState() => _GraphViewState();
}

const _nodeW = 188.0;
const _nodeH = 66.0;
const _gapX = 92.0;
const _gapY = 26.0;
const _pad = 28.0;

/// Positions of every node, by id, and the canvas size they need.
(Map<String, Offset>, Size) layoutGraph(ArchGraph g) {
  final ids = [for (final n in g.nodes) n.id];
  final outs = <String, List<String>>{for (final id in ids) id: []};
  final ins = <String, int>{for (final id in ids) id: 0};
  for (final e in g.edges) {
    if (!outs.containsKey(e.from) ||
        !outs.containsKey(e.to) ||
        e.from == e.to) {
      continue;
    }
    outs[e.from]!.add(e.to);
    ins[e.to] = ins[e.to]! + 1;
  }
  final linked = {
    for (final e in g.edges) e.from,
    for (final e in g.edges) e.to,
  };
  // Longest-path layering from the sources; a cycle is cut where it closes.
  final rank = <String, int>{};
  final visiting = <String>{};
  int visit(String id) {
    if (rank.containsKey(id)) return rank[id]!;
    if (visiting.contains(id)) return 0;
    visiting.add(id);
    var r = 0;
    for (final e in g.edges) {
      if (e.to == id && e.from != id && outs.containsKey(e.from)) {
        r = math.max(r, visit(e.from) + 1);
      }
    }
    visiting.remove(id);
    return rank[id] = r;
  }

  final columns = <int, List<String>>{};
  for (final id in ids.where(linked.contains)) {
    columns.putIfAbsent(visit(id), () => []).add(id);
  }
  // Unlinked nodes: a grid of columns after the layered part.
  final loose = ids.where((id) => !linked.contains(id)).toList();
  final firstLoose = columns.isEmpty ? 0 : columns.keys.reduce(math.max) + 1;
  final perColumn = math.max(4, math.sqrt(loose.length * 1.6).ceil());
  for (var i = 0; i < loose.length; i++) {
    columns.putIfAbsent(firstLoose + i ~/ perColumn, () => []).add(loose[i]);
  }

  final tallest = columns.values.fold<int>(0, (m, c) => math.max(m, c.length));
  final height =
      _pad * 2 + tallest * _nodeH + (tallest - 1).clamp(0, 999) * _gapY;
  final pos = <String, Offset>{};
  final keys = columns.keys.toList()..sort();
  for (var ci = 0; ci < keys.length; ci++) {
    final col = columns[keys[ci]]!;
    final colH = col.length * _nodeH + (col.length - 1) * _gapY;
    final top = (height - colH) / 2;
    for (var r = 0; r < col.length; r++) {
      pos[col[r]] = Offset(
        _pad + ci * (_nodeW + _gapX),
        top + r * (_nodeH + _gapY),
      );
    }
  }
  final width =
      _pad * 2 + keys.length * _nodeW + (keys.length - 1).clamp(0, 999) * _gapX;
  return (pos, Size(math.max(width, 200), math.max(height, 140)));
}

IconData kindIcon(String kind) => switch (kind) {
  'person' => Icons.person_outline,
  'client' => Icons.web_asset_outlined,
  'service' => Icons.dns_outlined,
  'data' => Icons.storage_outlined,
  'entity' => Icons.table_chart_outlined,
  'external' => Icons.cloud_outlined,
  'infra' => Icons.rocket_launch_outlined,
  'route' => Icons.alt_route,
  _ => Icons.folder_outlined,
};

class _GraphViewState extends State<GraphView> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GraphView old) {
    super.didUpdateWidget(old);
    if (old.graph.id != widget.graph.id) _controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final (pos, size) = layoutGraph(widget.graph);
    final selected = widget.selected;
    final near = <String>{
      if (selected != null)
        for (final e in widget.graph.edges)
          if (e.from == selected) e.to else if (e.to == selected) e.from,
    };
    return Semantics(
      label:
          '${widget.graph.title}: ${widget.graph.nodes.length} parts, '
          '${widget.graph.edges.length} links',
      child: Container(
        height: widget.height,
        decoration: ShapeDecoration(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              transformationController: _controller,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(240),
              minScale: 0.35,
              maxScale: 2.2,
              // Boxes have fixed sizes so the layout holds; larger text
              // is had by zooming the diagram, as with a map.
              child: MediaQuery.withNoTextScaling(
                child: SizedBox.fromSize(
                  size: size,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _EdgePainter(
                            graph: widget.graph,
                            pos: pos,
                            selected: selected,
                            line: p.hairlineStrong,
                            strong: p.accent,
                            label: p.textSecondary,
                            labelBg: p.surface,
                          ),
                        ),
                      ),
                      for (final n in widget.graph.nodes)
                        if (pos[n.id] != null)
                          Positioned(
                            left: pos[n.id]!.dx,
                            top: pos[n.id]!.dy,
                            width: _nodeW,
                            height: _nodeH,
                            child: _NodeBox(
                              node: n,
                              selected: n.id == selected,
                              dimmed:
                                  selected != null &&
                                  n.id != selected &&
                                  !near.contains(n.id),
                              onTap: () => widget.onSelect(n),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  _ZoomButton(
                    icon: Icons.remove,
                    tooltip: 'Zoom out',
                    onTap: () => _zoom(0.8),
                  ),
                  const SizedBox(width: 6),
                  _ZoomButton(
                    icon: Icons.add,
                    tooltip: 'Zoom in',
                    onTap: () => _zoom(1.25),
                  ),
                  const SizedBox(width: 6),
                  _ZoomButton(
                    icon: Icons.center_focus_strong_outlined,
                    tooltip: 'Reset view',
                    onTap: () => _controller.value = Matrix4.identity(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _zoom(double by) {
    final m = _controller.value.clone();
    final s = m.getMaxScaleOnAxis() * by;
    if (s < 0.35 || s > 2.2) return;
    _controller.value = m..scaleByDouble(by, by, 1, 1);
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: p.surfaceMuted,
        side: BorderSide(color: p.hairlineStrong),
        minimumSize: const Size(36, 36),
      ),
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox({
    required this.node,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });
  final GraphNode node;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final lines = node.label.split('\n');
    return AnimatedOpacity(
      opacity: dimmed ? 0.45 : 1,
      duration: LizMotion.of(context, LizMotion.quick),
      child: Material(
        color: selected ? p.surfaceHover : p.surfaceMuted,
        shape: LizRadius.shape(
          LizRadius.sm,
          side: BorderSide(
            color: selected ? p.accent : p.hairlineStrong,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: LizRadius.shape(LizRadius.sm),
          child: Semantics(
            button: true,
            selected: selected,
            label: node.label.replaceAll('\n', ', '),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    kindIcon(node.kind),
                    size: 18,
                    color: selected ? p.accent : p.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lines.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LizText.footnote.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (lines.length > 1 || node.detail != null)
                          Text(
                            lines.length > 1
                                ? lines.skip(1).join(' ')
                                : node.detail!.split('\n').first,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LizText.label.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.graph,
    required this.pos,
    required this.selected,
    required this.line,
    required this.strong,
    required this.label,
    required this.labelBg,
  });

  final ArchGraph graph;
  final Map<String, Offset> pos;
  final String? selected;
  final Color line;
  final Color strong;
  final Color label;
  final Color labelBg;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in graph.edges) {
      final a = pos[e.from];
      final b = pos[e.to];
      if (a == null || b == null || e.from == e.to) continue;
      final hot = selected != null && (e.from == selected || e.to == selected);
      final paint = Paint()
        ..color = hot ? strong : line
        ..strokeWidth = hot ? 1.8 : 1.2
        ..style = PaintingStyle.stroke;
      final forward = b.dx > a.dx;
      final start = forward
          ? a + const Offset(_nodeW, _nodeH / 2)
          : a + const Offset(_nodeW / 2, _nodeH);
      final end = forward
          ? b + const Offset(0, _nodeH / 2)
          : b + const Offset(_nodeW / 2, 0);
      final path = Path()..moveTo(start.dx, start.dy);
      if (forward) {
        final mx = (start.dx + end.dx) / 2;
        path.cubicTo(mx, start.dy, mx, end.dy, end.dx, end.dy);
      } else {
        final dy = (end.dy - start.dy).abs() / 2 + 30;
        path.cubicTo(
          start.dx,
          start.dy + dy,
          end.dx,
          end.dy - dy,
          end.dx,
          end.dy,
        );
      }
      canvas.drawPath(path, paint);
      // Arrowhead along the curve's last direction.
      final metric = path.computeMetrics().last;
      final tip = metric.getTangentForOffset(metric.length)!;
      final back = tip.vector * -8;
      final side = Offset(-tip.vector.dy, tip.vector.dx) * 4.5;
      canvas.drawPath(
        Path()
          ..moveTo(tip.position.dx, tip.position.dy)
          ..lineTo(
            tip.position.dx + back.dx + side.dx,
            tip.position.dy + back.dy + side.dy,
          )
          ..lineTo(
            tip.position.dx + back.dx - side.dx,
            tip.position.dy + back.dy - side.dy,
          )
          ..close(),
        Paint()..color = hot ? strong : line,
      );
      final text = e.label;
      if (text != null && text.isNotEmpty) {
        final mid = metric.getTangentForOffset(metric.length / 2)!.position;
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: LizText.label.copyWith(
              color: hot ? strong : label,
              fontSize: 11,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: _gapX + 40);
        final box = Rect.fromCenter(
          center: mid,
          width: tp.width + 8,
          height: tp.height + 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = labelBg,
        );
        tp.paint(canvas, box.topLeft + const Offset(4, 1));
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.graph != graph || old.selected != selected || old.line != line;
}
