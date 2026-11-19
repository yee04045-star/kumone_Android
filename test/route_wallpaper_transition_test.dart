import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/core/storage/wallpaper_store.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';
import 'package:kumone_flutter/ui/widgets/shell_chrome_transition.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
      'wallpaper route paints over outgoing content during push and pop',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('kumone-route-');
    final file = File('${root.path}/wall.png');
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final image = await recorder.endRecording().toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
    final wallpaper = WallpaperStore()..path = file.path..landscapePath = file.path;
    final settings = SettingsStore();
    final navigator = GlobalKey<NavigatorState>();
    final capture = GlobalKey();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: wallpaper),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: RepaintBoundary(
            key: capture,
            child: MaterialApp(
              navigatorKey: navigator,
              theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
              home: const ColoredBox(color: Colors.red),
            ))));
    await tester.runAsync(() async {
      await precacheImage(FileImage(file), navigator.currentContext!);
    });
    navigator.currentState!.push(kumonePageRoute<void>(
        const Scaffold(body: Center(child: Text('Independent page')))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    Future<void> checkPixel() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (400 * image.width + 750) * 4;
      final bytes = data!.buffer.asUint8List();
      // The new page's blue wallpaper must cover the old red page completely.
      expect(bytes[offset], lessThan(120));
      expect(bytes[offset + 2], greaterThan(200));
      image.dispose();
    }

    await tester.runAsync(checkPixel);
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(checkPixel);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    wallpaper.dispose();
    settings.dispose();
    await tester.runAsync(() async {
      await FileImage(file).evict();
      await root.delete(recursive: true);
    });
  });

  testWidgets('shell chrome reveals live glass without an opacity saveLayer',
      (tester) async {
    final visible = ValueNotifier(false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, show, __) => Align(
            alignment: Alignment.bottomCenter,
            child: KumoneShellChromeTransition(
                visible: show,
                child: const SizedBox(
                    width: 200, height: 100, child: Text('Mini + tabs')))),
      ),
    )));
    final shell = find.byType(KumoneShellChromeTransition);
    Rect visibleRect() {
      final finder =
          find.descendant(of: shell, matching: find.byType(ClipRect));
      final clip = tester.widget<ClipRect>(finder);
      return clip.clipper!.getClip(tester.getSize(finder));
    }

    expect(find.descendant(of: shell, matching: find.byType(FadeTransition)),
        findsNothing);
    expect(find.descendant(of: shell, matching: find.byType(Opacity)),
        findsNothing);
    expect(visibleRect().height, 0);
    visible.value = true;
    await tester.pump();
    expect(visibleRect().height, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(visibleRect().height, greaterThan(0));
    expect(visibleRect().height, lessThan(100));
    await tester.pumpAndSettle();
    expect(visibleRect().height, 100);
    visible.value = false;
    await tester.pump();
    expect(visibleRect().height, 0);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });
}
