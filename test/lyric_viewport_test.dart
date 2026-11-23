import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/lyric_viewport.dart';

void main() {
  testWidgets('lyrics retain text width and vertical bounds with horizontal blur room', (tester) async {
    const textKey = ValueKey('lyric-layout');
    await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(
      width: 300, height: 400, child: KumoneLyricViewport(
        child: SizedBox(key: textKey, width: double.infinity, height: double.infinity)),
    ))));
    expect(tester.getSize(find.byKey(textKey)), const Size(300, 400));
    final clip = find.descendant(of: find.byType(KumoneLyricViewport), matching: find.byType(ClipRect));
    expect(tester.getSize(clip), const Size(364, 400));
    final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    expect(mask.blendMode, BlendMode.dstIn);
    expect(tester.takeException(), isNull);
  });
}
