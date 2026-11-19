import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/marquee_text.dart';
import 'package:kumone_flutter/ui/widgets/lyric_effects.dart';

void main() {
  test('bidirectional blur keeps active and browsing lines clear', () {
    expect(lyricBlurRadius(4, 4, 5, false), 0);
    expect(lyricBlurRadius(1, 4, 5, true), 0);
    expect(lyricBlurRadius(1, 4, 0, false), 0);
    expect(lyricBlurRadius(3, 4, 5, false), lyricBlurRadius(5, 4, 5, false));
    expect(lyricBlurRadius(1, 4, 5, false),
        greaterThan(lyricBlurRadius(3, 4, 5, false)));
  });
  test('CJK glow requires a long timed pure CJK word', () {
    expect(cjkLongNote('你，', 1500), true);
    expect(cjkLongNote('かな', 2400), true);
    expect(cjkLongNote('한', 1200), true);
    expect(cjkLongNote('你', 300), false);
    expect(cjkLongNote('hello', 3000), false);
    expect(cjkLongNote('你a', 3000), false);
  });
  testWidgets('overflow title pauses then scrolls, changing song resets it',
      (tester) async {
    const title = 'This is a very very very long song title';
    Widget view(String text) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 110, child: MarqueeText(text))));
    await tester.pumpWidget(view(title));
    final transform = find.descendant(
        of: find.byType(MarqueeText), matching: find.byType(Transform));
    expect(tester.widget<Transform>(transform).transform.storage[12], 0);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Transform>(transform).transform.storage[12], 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(
        tester.widget<Transform>(transform).transform.storage[12], lessThan(0));
    await tester.pumpWidget(view('Short'));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byType(MarqueeText), matching: find.byType(Transform)),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
