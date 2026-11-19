import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/theme/player_surface_theme.dart';

void main() {
  for (final base in [ThemeData.light(), ThemeData.dark()]) {
    test('player menu contrast ignores ${base.brightness} appearance', () {
      final dark = kumonePlayerSurfaceTheme(base, const Color(0xFF202030), Colors.black);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.onSurface.computeLuminance(), greaterThan(.5));
      final light = kumonePlayerSurfaceTheme(base, Colors.white, const Color(0xFFF0F0F0));
      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.onSurface.computeLuminance(), lessThan(.1));
      expect(kumonePlayerSurfaceTheme(base, null, null), same(base));
    });
  }
}
