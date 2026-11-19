import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/cached_wallpaper.dart';

void main() {
  testWidgets('cached Gaussian wallpaper preserves bright edges and target size', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('wallpaper-cache');
      try {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final source = await recorder.endRecording().toImage(16, 16);
        final png = await source.toByteData(format: ui.ImageByteFormat.png);
        final file = File('${root.path}/wall.png');
        await file.writeAsBytes(png!.buffer.asUint8List());
        source.dispose();
        final result = await CachedWallpaper.renderForTest(file.path, 48, 80, 20);
        expect(result.width, 48);
        expect(result.height, 80);
        final pixels = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(pixels!.getUint8(0), greaterThan(240));
        expect(pixels.getUint8(3), greaterThan(240));
        result.dispose();
      } finally { await root.delete(recursive: true); }
    });
  });
}
