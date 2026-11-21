import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';
import 'package:kumone_flutter/ui/widgets/marquee_text.dart';

void main() {
  testWidgets('category stays pinned while root title scrolls away', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomScrollView(
      slivers: [const KumoneScrollingTabHeader(title: Text('精选'),
        bottom: PreferredSize(preferredSize: Size.fromHeight(46),
          child: SizedBox(height: 46, child: Center(child: Text('分类'))))),
        SliverList.builder(itemCount: 50, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')))],
    ))));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('分类')).dy, lessThan(46));
    expect(tester.takeException(), isNull);
  });
  testWidgets('non-current preview lines never start a marquee', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
      width: 100, child: MarqueeText('Long preview lyric ' * 20,
        scrollEnabled: false, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20))))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.descendant(of: find.byType(MarqueeText),
        matching: find.byType(AnimatedBuilder)), findsNothing);
    final text = tester.widget<Text>(find.text('Long preview lyric ' * 20));
    expect(text.overflow, TextOverflow.ellipsis);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('short centered marquee uses the full available title width', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(
      width: 400, child: MarqueeText('Song', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20))))));
    final text = tester.widget<Text>(find.text('Song'));
    expect(text.textAlign, TextAlign.center);
    expect(tester.getSize(find.text('Song')).width, 400);
    await tester.pumpWidget(const SizedBox());
  });
}
