import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/core/storage/wallpaper_store.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('player theme conflicting with wallpaper still restores wallpaper contrast', (tester) async {
    final settings = SettingsStore();
    final wallpaper = WallpaperStore()..path = 'wall.png'..landscapePath = 'wall.png';
    for (final dark in [true, false]) {
      wallpaper.dark = dark;
      wallpaper.landscapeDark = dark;
      wallpaper.landscapeStatusColor = dark ? Colors.black : Colors.white;
      wallpaper.statusColor = dark ? Colors.black : Colors.white;
      SystemUiOverlayStyle? style;
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: wallpaper),
      ], child: MaterialApp(theme: ThemeData(brightness: dark ? Brightness.light : Brightness.dark),
        home: Builder(builder: (context) {
          style = kumoneGlassStatusBarStyle(context);
          return const SizedBox();
        }),
      )));
      expect(style!.statusBarIconBrightness, dark ? Brightness.light : Brightness.dark);
      await tester.pumpWidget(const SizedBox());
    }
    settings.dispose(); wallpaper.dispose();
  });
  for (final sliver in [false, true]) {
    testWidgets('${sliver ? 'sliver' : 'regular'} glass toolbar chooses contrasting status icons', (tester) async {
      final settings = SettingsStore();
      final wallpaper = WallpaperStore();
      for (final dark in [false, true]) {
        for (final custom in [false, true]) {
          wallpaper.path = custom ? 'test-wallpaper.png' : null;
          wallpaper.landscapePath = wallpaper.path;
          wallpaper.landscapeDark = dark;
          wallpaper.landscapeStatusColor = dark ? Colors.black : Colors.white;
          wallpaper.dark = dark;
          wallpaper.statusColor = dark ? Colors.black : Colors.white;
          await tester.pumpWidget(MultiProvider(providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: wallpaper),
          ], child: MaterialApp(theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
            home: sliver ? const Scaffold(body: CustomScrollView(slivers: [
              KumoneGlassSliverAppBar(title: Text('Sliver')),
            ])) : const Scaffold(appBar: KumoneGlassAppBar(title: Text('Detail'))),
          )));
          await tester.pump();
          final bar = tester.widget<AppBar>(find.byType(AppBar));
          expect(bar.systemOverlayStyle!.statusBarIconBrightness,
            dark ? Brightness.light : Brightness.dark);
          expect(bar.systemOverlayStyle!.statusBarBrightness,
            dark ? Brightness.dark : Brightness.light);
          expect(bar.systemOverlayStyle!.statusBarColor, Colors.transparent);
          expect(bar.systemOverlayStyle!.systemStatusBarContrastEnforced, false);
          final region = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).last;
          expect(region.value.statusBarIconBrightness,
            dark ? Brightness.light : Brightness.dark);
          await tester.pumpWidget(const SizedBox());
        }
      }
      settings.dispose(); wallpaper.dispose();
    });
  }
}
