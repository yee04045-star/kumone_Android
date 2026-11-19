import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/pages/wallpaper_crop_page.dart';

void main() {
  testWidgets('wallpaper crop confirms only the visible frame', (tester) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final image = await recorder.endRecording().toImage(100, 100);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List(); image.dispose();
    });
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
          builder: (_) => WallpaperCropPage(bytes: bytes, aspectRatio: .5)));
      }, child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    final viewerFinder = find.byType(InteractiveViewer);
    final controller = tester.widget<InteractiveViewer>(viewerFinder).transformationController!;
    final initial = controller.value.clone();
    await tester.drag(viewerFinder, const Offset(45, 0));
    await tester.pumpAndSettle();
    expect(controller.value.storage[12], isNot(initial.storage[12]));
    final center = tester.getCenter(viewerFinder);
    final first = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final second = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await tester.pump();
    await first.moveTo(center - const Offset(65, 0));
    await second.moveTo(center + const Offset(65, 0));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    await first.up(); await second.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置构图'));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(controller.value.storage[12], closeTo(initial.storage[12], .01));
    await tester.tap(find.text('使用此裁切'));
    await tester.pump();
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(result!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width / frame.image.height, closeTo(.5, .01));
      frame.image.dispose(); codec.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
