import 'package:kumone_flutter/ui/widgets/cached_wallpaper.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/core/storage/wallpaper_store.dart';
import 'package:kumone_flutter/ui/widgets/wallpaper_scope.dart';
import 'package:kumone_flutter/ui/widgets/original_player_theme.dart';
import 'package:kumone_flutter/ui/theme/app_theme.dart';

void main() {
  setUp(() => CachedWallpaper.cacheEnabled = false);
  tearDown(() => CachedWallpaper.cacheEnabled = true);
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('kumone-wallpaper-test');
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  testWidgets(
      'wallpaper theme reaches pushed routes but player uses original appearance',
      (tester) async {
    final file = File(p.join(root.path, 'wall.png'));
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.black, BlendMode.src);
      final image = await recorder.endRecording().toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.writeAsBytes(Uint8List.view(data!.buffer));
      image.dispose();
    });
    final wallpaper = WallpaperStore()
      ..path = file.path
      ..landscapePath = file.path
      ..landscapeDark = true
      ..dark = true;
    final settings = SettingsStore()..appearance = AppearanceMode.light;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: wallpaper),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => WallpaperScope(child: child!),
          home: Builder(
              builder: (context) =>
                  Scaffold(body: Text(Theme.of(context).brightness.name))),
        )));
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Builder(
            builder: (context) => Scaffold(
                body: Text('detail:${Theme.of(context).brightness.name}')))));
    await tester.pumpAndSettle();
    expect(find.text('detail:dark'), findsOneWidget);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => OriginalPlayerTheme(
            child: Builder(
                builder: (context) => Scaffold(
                    body: Text(
                        'player:${Theme.of(context).brightness.name}'))))));
    await tester.pumpAndSettle();
    expect(find.text('player:light'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(CachedWallpaper.settlePending);
    wallpaper.dispose();
    settings.dispose();
  });

  testWidgets('background extend setting drives the app status-bar tint',
      (tester) async {
    final file = File(p.join(root.path, 'wall_extend.png'));
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.black, BlendMode.src);
      final image = await recorder.endRecording().toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.writeAsBytes(Uint8List.view(data!.buffer));
      image.dispose();
    });
    final wallpaper = WallpaperStore()..path = file.path..landscapePath = file.path;
    await tester.runAsync(wallpaper.sampleStatusColor);
    await tester.runAsync(() => wallpaper.sampleStatusColor(landscape: true));
    final settings = SettingsStore();
    // Extending the background behind the status bar is the default.
    expect(settings.backgroundExtend, isTrue);

    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: wallpaper),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          builder: (_, child) => WallpaperScope(child: child!),
          home: const Scaffold(body: SizedBox.shrink()),
        )));
    await tester.pumpAndSettle();
    AnnotatedRegion<SystemUiOverlayStyle> region() =>
        tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>));
    // Extended: transparent bars so the wallpaper shows through.
    expect(region().value.statusBarColor, Colors.transparent);

    await settings.setBackgroundExtend(false);
    await tester.pumpAndSettle();
    // Not extended: a solid theme strip instead of the wallpaper.
    expect(region().value.statusBarColor, isNot(Colors.transparent));
    expect(wallpaper.statusColor, Colors.black);
    expect(region().value.statusBarColor,
        Color.alphaBlend(Colors.white.withValues(alpha: .24), Colors.black));
    expect(region().value.statusBarColor,
        isNot(KumoneTheme.light().scaffoldBackgroundColor));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(CachedWallpaper.settlePending);
    wallpaper.dispose();
    settings.dispose();
  });
}
