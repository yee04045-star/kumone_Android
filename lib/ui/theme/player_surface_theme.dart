import 'package:flutter/material.dart';

// Menus over the player follow its actual ambient colors, not app appearance.
ThemeData kumonePlayerSurfaceTheme(ThemeData base, Color? primary, Color? secondary) {
  if (primary == null) return base;
  final background = Color.lerp(primary, secondary ?? primary, .42)!;
  final brightness = background.computeLuminance() > .5
      ? Brightness.light : Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: base.colorScheme.primary,
      brightness: brightness).copyWith(primary: base.colorScheme.primary);
  return base.copyWith(brightness: brightness, colorScheme: scheme,
      textTheme: (brightness == Brightness.dark
          ? ThemeData.dark().textTheme : ThemeData.light().textTheme),
      iconTheme: IconThemeData(color: scheme.onSurface));
}
