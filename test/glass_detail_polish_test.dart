import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:kumone_flutter/core/models/lyrics.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/pages/now_playing_page.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';
import 'package:kumone_flutter/ui/widgets/glass_category_chip.dart';
import 'package:kumone_flutter/ui/widgets/glass_side_navigation.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('immersive lyrics really resize plain, karaoke and furigana text',
      (tester) async {
    final settings = SettingsStore()..verbatim = false;
    const line = LyricLine(
        startMs: 0,
        text: '歌声',
        translation: 'Translation',
        romaji: 'romaji',
        words: [LyricWord('歌声', 0, 1000)],
        furigana: [FuriganaSegment('歌声', 'うたごえ')]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
          home: Scaffold(
              body: Consumer<SettingsStore>(
        builder: (_, settings, __) => KumoneImmersiveLyricLine(
            line: line, current: true, settings: settings, playbackMs: 500),
      ))),
    ));
    expect(tester.widget<Text>(find.text('歌声')).style!.fontSize, 28.6);
    settings.previewLyricFontScale(1.8);
    await tester.pump();
    expect(tester.widget<Text>(find.text('歌声')).style!.fontSize,
        closeTo(46.8, .001));
    expect(tester.widget<Text>(find.text('Translation')).style!.fontSize,
        closeTo(28.8, .001));
    settings.verbatim = true;
    settings.previewLyricFontScale(.8);
    await tester.pump();
    final karaoke = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => t.textSpan != null);
    final spans = (karaoke.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style!.fontSize, closeTo(20.8, .001));
    settings.verbatim = false;
    settings.annotation = LyricsAnnotationMode.furigana;
    settings.previewLyricFontScale(1.8);
    await tester.pump();
    expect(tester.widget<Text>(find.text('うたごえ')).style!.fontSize,
        closeTo(19.8, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('top frost fades continuously without a heavy scrim and keeps its full extent',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 28);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final categories in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: CustomScrollView(slivers: [
            KumoneGlassSliverAppBar(
              title: const Text('精选'),
              bottom: categories ? const PreferredSize(
                preferredSize: Size.fromHeight(54),
                child: SizedBox(height: 54)) : null,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 1200)),
          ])),
        ));
        final finder = find.byType(LiquidGlassScrollEdge);
        final edge = tester.widget<LiquidGlassScrollEdge>(finder);
        expect(edge.blur, 26);
        expect(edge.color.a, closeTo(.10, .001));
        expect(edge.style, LiquidGlassScrollEdgeStyle.soft);
        expect(edge.blurCurve.transform(.25), greaterThan(0));
        expect(edge.blurCurve.transform(.5), closeTo(.5, .001));
        expect(edge.blurCurve.transform(.8), greaterThan(.8));
        expect(edge.blurCurve.transform(1), 1);
        expect(edge.curve.transform(.5), closeTo(edge.blurCurve.transform(.5), .001));
        expect(tester.getTopLeft(finder).dy, 0);
        expect(tester.getSize(finder).height,
            kToolbarHeight + 28 + (categories ? 54 : 0));
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(tester.getSize(finder).height,
            kToolbarHeight + 28 + (categories ? 54 : 0));
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
      'selected category uses neutral glass not a blue outline or check',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: GlassCategoryChip(label: '专辑', selected: true, onTap: () {}),
    ))));
    expect(find.byIcon(Icons.check), findsNothing);
    final context = tester.element(find.text('专辑'));
    expect(tester.widget<Text>(find.text('专辑')).style!.color,
        Theme.of(context).colorScheme.onSurface);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded panel waits one second then drags without selecting',
      (tester) async {
    double? saved;
    bool? left;
    int? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: KumoneGlassSideNavigation(
      selectedIndex: 0,
      onChanged: (i) => selected = i,
      onExpand: () {},
      expandedPosition: .5,
      onPositionChanged: (p, l) {
        saved = p;
        left = l;
      },
      labels: const ['推荐', '精选', '搜索', '我的'],
      icons: const [Icons.home, Icons.grid_view, Icons.search, Icons.person],
    ))));
    expect(find.byType(LiquidGlassMotionPill), findsOneWidget);
    final tab = find.byKey(const ValueKey('floating-tab-1'));
    final origin = tester.getCenter(tab);
    final gesture = await tester.startGesture(origin);
    await tester.pump(const Duration(milliseconds: 990));
    expect(saved, null);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-650, -120));
    await tester.pump();
    expect(tester.getCenter(tab).dy, lessThan(origin.dy));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saved, lessThan(.5));
    expect(left, true);
    expect(selected, null);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
