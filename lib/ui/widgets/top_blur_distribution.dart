import 'dart:math' as math;
import 'package:flutter/animation.dart';

// LiquidGlassScrollEdge uses 1 - curve(t) as blur coverage. Raising the
// original curve to a power delays clearing smoothly, without a hard plateau
// or changing the blur sigma, tint or band height. 1 is exactly the old curve.
class KumoneTopBlurDistribution extends Curve {
  final double distribution;
  const KumoneTopBlurDistribution(this.distribution);

  @override
  double transformInternal(double t) => math
      .pow(Curves.easeInOut.transform(t), distribution.clamp(.5, 6))
      .toDouble();

  @override
  bool operator ==(Object other) =>
      other is KumoneTopBlurDistribution && other.distribution == distribution;

  @override
  int get hashCode => distribution.hashCode;
}
