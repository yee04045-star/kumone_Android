import 'package:flutter/material.dart';

// Widen only the paint bounds, not the text layout. The mask and clip share
// the same vertical bounds so overflow cannot bypass the top/bottom fade.
class KumoneLyricViewport extends StatelessWidget {
  final Widget child;
  const KumoneLyricViewport({super.key, required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => OverflowBox(
      alignment: Alignment.center,
      minWidth: bounds.maxWidth + 64,
      maxWidth: bounds.maxWidth + 64,
      child: ClipRect(child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          stops: [0, .12, .84, 1],
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        ).createShader(rect),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
          child: child),
      )),
    ),
  );
}
