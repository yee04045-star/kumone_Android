import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

// Distance-based bidirectional blur, independently implemented for Flutter.
double lyricBlurRadius(int index, int active, double strength, bool browsing) {
  if (browsing || index == active || strength <= 0) return 0;
  final distance = (index - active).abs();
  return strength * math.min(1.0, .35 + distance * .22);
}

bool cjkLongNote(String text, int durationMs) {
  final body = text.replaceAll(
      RegExp(r'[\s\u3000-\u303f\uff00-\uff65.,!?，。！？、…「」『』（）“”‘’：；]'), '');
  final count = body.runes.length;
  return count >= 1 &&
      count <= 3 &&
      durationMs >= count * 1000 &&
      RegExp(r'^[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]+$').hasMatch(body);
}

class LyricDistanceBlur extends StatelessWidget {
  final double radius;
  final Widget child;
  const LyricDistanceBlur(
      {super.key, required this.radius, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: radius),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        builder: (_, value, child) => ImageFiltered(
          enabled: value > .01,
          imageFilter: ImageFilter.blur(sigmaX: value, sigmaY: value),
          child: child,
        ),
        child: child,
      );
}
