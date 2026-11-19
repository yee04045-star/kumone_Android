import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/player_dual_pane.dart';

void main() {
  for (final size in [
    const Size(740, 280),
    const Size(844, 330),
    const Size(1024, 680),
    const Size(1366, 930),
    const Size(900, 1150)
  ]) {
    testWidgets('two-pane player fits $size without divider', (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: KumonePlayerDualPane(
        playerBuilder: (cover, spacious) =>
            Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(key: const Key('cover'), width: cover, height: cover),
          SizedBox(height: spacious ? 310 : 170, child: const Text('Controls')),
        ]),
        lyrics: const ColoredBox(
            key: Key('lyrics'),
            color: Colors.transparent,
            child: Center(child: Text('Lyrics'))),
      ))));
      expect(tester.takeException(), isNull);
      expect(find.byType(VerticalDivider), findsNothing);
      final cover = tester.getRect(find.byKey(const Key('cover')));
      final lyrics = tester.getRect(find.byKey(const Key('lyrics')));
      expect(cover.width, greaterThanOrEqualTo(64));
      expect(cover.right, lessThan(lyrics.left));
      expect(lyrics.width, greaterThan(size.width * .4));
      expect(tester.getRect(find.text('Controls')).bottom,
          lessThanOrEqualTo(size.height));
    });
  }
}
