import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Paint the scrollable exactly once. Repainting a composited scrollable under
// several clips reparents its layers and can leave only the last strip visible.
class ScrollTextEdges extends StatelessWidget {
  final double left, right;
  final Widget child;
  const ScrollTextEdges({super.key, required this.left, required this.right,
    required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final edge = (14 / bounds.maxWidth).clamp(0.0, .45);
    Widget blurEdge(double amount, bool atLeft) => Positioned(
      left: atLeft ? 0 : null, right: atLeft ? null : 0,
      top: 0, bottom: 0, width: bounds.maxWidth * edge,
      child: IgnorePointer(child: ClipRect(child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: atLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: atLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
        child: BackdropFilter(
          enabled: amount > .001,
          filter: ui.ImageFilter.blur(sigmaX: 1.2 * amount, sigmaY: 1.2 * amount),
          child: const SizedBox.expand(),
        ),
      ))));
    // Keep the hierarchy stable when overflow measurements first arrive.
    return ClipRect(child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        stops: [0, edge * .35, edge, 1 - edge, 1 - edge * .35, 1],
        colors: [Colors.white.withValues(alpha: 1 - left),
          Colors.white.withValues(alpha: 1 - left * .55), Colors.white,
          Colors.white, Colors.white.withValues(alpha: 1 - right * .55),
          Colors.white.withValues(alpha: 1 - right)],
      ).createShader(rect),
      child: Stack(fit: StackFit.passthrough, children: [
        child, blurEdge(left, true), blurEdge(right, false),
      ]),
    ));
  });
}
