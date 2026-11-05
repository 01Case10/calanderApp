import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Clumsy scissors-cut paper — LOCKED 2026-10-28.
///
/// Rules, all enforced here so no other widget can drift back:
/// - Exactly 4 sides, straight lines only. No serration, no torn points,
///   no squiggly edges.
/// - Corners shifted 15-35px equivalent (4-8% of width/height), so
///   top != bottom, left != right. Visibly hand-cut, not uniform.
/// - Shadow is the EXACT same quad translated by [shadowOffset].
///   Never a new random shape — that mismatch was the squiggly bug.
/// - Deterministic by [seed]: same seed always gives the same quad,
///   on every launch and both platforms. No Random() at build time.
///
/// The quad is defined in normalised 0..1 coordinates, so it scales
/// to any screen size without changing its clumsy character.
List<Offset> clumsyQuadForSeed(int seed) {
  // Simple deterministic hash, no Random().
  int h(int i) => (seed * 37 + i * 17 + 11) % 100;
  double j(int i, double max) => -0.01 + (h(i) / 100.0) * max;
  return [
    Offset(0.01 + j(0, 0.04), 0.0 + j(1, 0.06)),
    Offset(0.99 - j(2, 0.04), 0.0 + j(3, 0.06)),
    Offset(0.99 - j(4, 0.04), 1.0 - j(5, 0.06)),
    Offset(0.01 + j(6, 0.04), 1.0 - j(7, 0.06)),
  ];
}

class ClumsyPaperPainter extends CustomPainter {
  final List<Offset> quad;
  final Color fill;
  final Offset shadowOffset;
  const ClumsyPaperPainter({
    required this.quad,
    required this.fill,
    this.shadowOffset = const Offset(8, 8),
  });

  Path _path(Size size, Offset offset) {
    final path = Path();
    for (var i = 0; i < quad.length; i++) {
      final p = Offset(
        quad[i].dx * size.width + offset.dx,
        quad[i].dy * size.height + offset.dy,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Shadow first, exact same shape translated.
    canvas.drawPath(
      _path(size, shadowOffset),
      Paint()..color = AppColors.black,
    );
    // Fill, then straight black outline.
    canvas.drawPath(_path(size, Offset.zero), Paint()..color = fill);
    canvas.drawPath(
      _path(size, Offset.zero),
      Paint()
        ..color = AppColors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(covariant ClumsyPaperPainter old) =>
      old.quad != quad ||
      old.fill != fill ||
      old.shadowOffset != shadowOffset;
}

/// A piece of paper pasted on the page, clumsily cut.
/// [seed] controls the quad shape; [rotationDegrees] controls how
/// crookedly it is pasted (-8..+8 for small scraps, per locked rule).
///
/// Phase 2 press feedback: on tap-down the scrap scales to 0.96 and its
/// shadow tucks toward the paper (8 -> 4); on release/cancel it eases
/// back. No ripple (NoSplash stays). [semanticLabel], when given,
/// replaces the descendant text for screen readers.
class ClumsyPaper extends StatefulWidget {
  final Widget child;
  final Color color;
  final int seed;
  final double rotationDegrees;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  const ClumsyPaper({
    super.key,
    required this.child,
    this.color = AppColors.white,
    this.seed = 0,
    this.rotationDegrees = 0,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  @override
  State<ClumsyPaper> createState() => _ClumsyPaperState();
}

class _ClumsyPaperState extends State<ClumsyPaper> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if ((widget.onTap == null && widget.onLongPress == null) ||
        _pressed == v) {
      return;
    }
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final quad = clumsyQuadForSeed(widget.seed);
    final content = CustomPaint(
      painter: ClumsyPaperPainter(
        quad: quad,
        fill: widget.color,
        shadowOffset:
            _pressed ? const Offset(4, 4) : const Offset(8, 8),
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    final rotated = Transform.rotate(
      angle: widget.rotationDegrees * math.pi / 180,
      child: content,
    );
    // AnimatedScale is idle at 1.0 when there is no tap handler.
    final scaled = AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: rotated,
    );
    if (widget.onTap == null && widget.onLongPress == null) {
      return scaled;
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _setPressed(false);
                widget.onLongPress!();
              },
        child: scaled,
      ),
    );
  }
}
