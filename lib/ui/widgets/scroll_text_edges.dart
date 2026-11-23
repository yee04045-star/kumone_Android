import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// A single content tree preserves metadata links, semantics and scroll state.
class ScrollTextEdges extends StatelessWidget {
  final double left, right;
  final Widget child;
  const ScrollTextEdges({super.key, required this.left, required this.right,
    required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    // Keep the hierarchy stable as overflow measurements become available;
    // otherwise the scrollable is remounted and an active scroll is cancelled.
    final edge = (14 / bounds.maxWidth).clamp(0.0, .45);
    return ClipRect(child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        stops: [0, edge * .35, edge, 1 - edge, 1 - edge * .35, 1],
        colors: [Colors.white.withValues(alpha: 1 - left),
          Colors.white.withValues(alpha: 1 - left * .55), Colors.white,
          Colors.white, Colors.white.withValues(alpha: 1 - right * .55),
          Colors.white.withValues(alpha: 1 - right)],
      ).createShader(rect), child: _EdgeBlur(left: left, right: right, child: child)));
  });
}

// Repaint the same render child through disjoint clips. This keeps one widget
// tree (and one set of links/semantics) while filtering only its outer pixels.
class _EdgeBlur extends SingleChildRenderObjectWidget {
  final double left, right;
  const _EdgeBlur({required this.left, required this.right, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEdgeBlur(left, right);
  @override
  void updateRenderObject(BuildContext context, _RenderEdgeBlur renderObject) {
    renderObject.update(left, right);
  }
}
class _RenderEdgeBlur extends RenderProxyBox {
  double left, right;
  _RenderEdgeBlur(this.left, this.right);
  void update(double nextLeft, double nextRight) {
    if (left == nextLeft && right == nextRight) return;
    left = nextLeft; right = nextRight; markNeedsPaint();
  }
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    if (left <= .001 && right <= .001) {
      super.paint(context, offset);
      return;
    }
    final edge = (size.width / 2).clamp(0.0, 14.0);
    final l = left > .001 ? edge : 0.0;
    final r = right > .001 ? edge : 0.0;
    void region(Rect rect, double sigma) {
      if (rect.isEmpty) return;
      context.pushClipRect(true, offset, rect, (clipped, origin) {
        if (sigma > 0) {
          clipped.pushLayer(ImageFilterLayer(imageFilter:
            ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)),
            (filtered, location) => super.paint(filtered, location), origin);
        } else {
          super.paint(clipped, origin);
        }
      });
    }
    region(Rect.fromLTRB(l, 0, size.width - r, size.height), 0);
    const bands = 4;
    for (var i = 0; i < bands; i++) {
      final a = edge * i / bands, b = edge * (i + 1) / bands;
      final strength = 1.0 - (i + .5) / bands;
      if (l > 0) {
        region(Rect.fromLTRB(a, 0, b, size.height), 1.2 * left * strength);
      }
      if (r > 0) {
        region(Rect.fromLTRB(size.width - b, 0, size.width - a, size.height),
          1.2 * right * strength);
      }
    }
  }
}
