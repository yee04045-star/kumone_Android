import 'dart:ui';
import 'package:flutter/material.dart';

class KumoneBottomOverlayInset extends InheritedWidget {
  final double inset;

  const KumoneBottomOverlayInset({
    super.key,
    required this.inset,
    required super.child,
  });

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KumoneBottomOverlayInset>()?.inset ?? 0.0;

  @override
  bool updateShouldNotify(KumoneBottomOverlayInset oldWidget) =>
      inset != oldWidget.inset;
}

class KumoneTheme {
  static const accent = Color(0xFFEC4949);
  static const accentDeep = Color(0xFFC92929);
  static const systemBlue = Color(0xFF0A84FF);

  static ThemeData light({Color color = systemBlue}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: systemBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: color,
          onPrimary: color.computeLuminance() > .4 ? Colors.black : Colors.white,
          secondary: color,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F8FA),
      );

  static ThemeData dark({Color color = systemBlue}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: systemBlue,
          brightness: Brightness.dark,
        ).copyWith(
          primary: color,
          onPrimary: color.computeLuminance() > .4 ? Colors.black : Colors.white,
          secondary: color,
        ),
        scaffoldBackgroundColor: const Color(0xFF101012),
      );
}

class GlassDecoration extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final double blur;
  final Color? color;
  final double opacity;
  final EdgeInsetsGeometry? padding;

  const GlassDecoration({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(18)),
    this.blur = 18,
    this.color,
    this.opacity = 0.74,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final fill = (color ?? Theme.of(context).colorScheme.surface)
        .withValues(alpha: opacity.clamp(0.0, 1.0).toDouble());
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: .16),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Spacing {
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}
