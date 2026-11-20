import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/auto_scroll_metadata.dart';

void main() {
  testWidgets('short metadata stays centered when track identity changes', (tester) async {
    Future<void> show(String text) => tester.pumpWidget(MaterialApp(home: Center(
      child: SizedBox(width: 400, height: 30, child: AutoScrollMetadata(
        centered: true, identity: text, child: Text(text, style: const TextStyle(fontSize: 12)))),
    )));
    await show('Artist · Album');
    final viewport = find.byType(SingleChildScrollView);
    expect(tester.getCenter(find.text('Artist · Album')).dx,
        closeTo(tester.getCenter(viewport).dx, .1));
    await show('Other');
    await tester.pump();
    expect(tester.getCenter(find.text('Other')).dx,
        closeTo(tester.getCenter(viewport).dx, .1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('long centered metadata remains horizontally scrollable', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 180,
      height: 30, child: AutoScrollMetadata(centered: true, identity: 'long',
        child: Text('Artist and album ' * 20))))));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
