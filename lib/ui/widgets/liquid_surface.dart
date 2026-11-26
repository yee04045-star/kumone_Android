import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// The optical settings every piece of navigation chrome shares.
///
/// The mini player and the bottom tab bar sit a few pixels apart, so they
/// must read as the same sheet of glass. Keeping the numbers here — instead
/// of inline in each widget — stops one surface from drifting to a heavier,
/// more opaque frost than the one beside it (the tab bar used to carry the
/// package's `defaultStyle`, a 68%-opaque white wash, which read as a flat
/// backing layer under the bar).
class KumoneGlassOptics {
  const KumoneGlassOptics._();

  /// Frost behind the glass: a light wash in light mode, a dark one in dark
  /// mode. Low enough that the page stays legible through the chrome.
  static double backingOpacity(Brightness brightness) =>
      brightness == Brightness.dark ? .30 : .24;

  /// [backingOpacity] as a color to tint the glass with.
  static Color backingColor(Brightness brightness) =>
      (brightness == Brightness.dark ? Colors.black : Colors.white)
          .withValues(alpha: backingOpacity(brightness));

  static const double blur = 6;
  static const double saturation = 1.15;
  static const double refractionIndex = 1.08;
  static const double refractionWidth = 18;
  static const double magnification = 1.015;
  static const double dispersion = 1.0;

  /// Rewrites the optical facets of [base] to the shared chrome look while
  /// keeping its shape, specular highlights and contact shadow. Callers pass
  /// their own base so a bar keeps its tuned capsule while matching the
  /// tint, blur and refraction of the rest of the chrome.
  static LiquidGlassStyle applyTo(
    LiquidGlassStyle base,
    Brightness brightness,
  ) =>
      base.copyWith(
        color: backingColor(brightness),
        blur: blur,
        saturation: saturation,
        refractionIndex: refractionIndex,
        refractionWidth: refractionWidth,
        magnification: magnification,
        dispersion: dispersion,
      );
}

// Navigation chrome owns its optical settings. Menu opacity never reaches here.
class KumoneLiquidSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? backingOpacity;
  final double? blur;
  final bool interactive;
  final bool liteGlass;
  final double revealProgress;

  const KumoneLiquidSurface({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.backingOpacity,
    this.blur,
    this.interactive = true,
    this.liteGlass = false,
    this.revealProgress = 1,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LiquidGlassLens(
      touch:
          reduceMotion || !interactive
              ? null : const LiquidGlassTouch(flex: LiquidGlassFlex()),
      style: LiquidGlassStyle(
        liteGlass: liteGlass,
        shape:
            LiquidGlassShape.continuousRoundedRectangle(cornerRadius: radius),
        color: backingOpacity == null
            ? KumoneGlassOptics.backingColor(brightness).withValues(alpha: KumoneGlassOptics.backingOpacity(brightness) * revealProgress)
            : (dark ? Colors.black : Colors.white)
                .withValues(alpha: backingOpacity! * revealProgress),
        blur: revealProgress * (blur ?? (backingOpacity == null
            ? (context.watch<SettingsStore?>()?.chromeBlur ??
                KumoneGlassOptics.blur)
            : 14)),
        refractionIndex: 1 + (KumoneGlassOptics.refractionIndex - 1) * revealProgress,
        refractionWidth: KumoneGlassOptics.refractionWidth * revealProgress,
        magnification: 1 + (KumoneGlassOptics.magnification - 1) * revealProgress,
        dispersion: KumoneGlassOptics.dispersion,
        saturation: 1 + (KumoneGlassOptics.saturation - 1) * revealProgress,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
