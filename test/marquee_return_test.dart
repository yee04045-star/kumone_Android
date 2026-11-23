import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/marquee_text.dart';

void main() {
  testWidgets('marquee smoothly returns instead of jumping to start', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(
      width: 100, child: MarqueeText('A sufficiently long scrolling song title',
        pixelsPerSecond: 10000)))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    double x() => tester.widget<Transform>(find.descendant(
      of: find.byType(MarqueeText), matching: find.byType(Transform)).first)
      .transform.storage[12];
    final end = x();
    expect(end, lessThan(0));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(x(), greaterThan(end));
    expect(x(), lessThan(0));
    await tester.pump(const Duration(seconds: 1));
    expect(x(), closeTo(0, .01));
    await tester.pumpWidget(const SizedBox());
  });
}
