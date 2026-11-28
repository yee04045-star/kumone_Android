import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:kumone_flutter/core/models/models.dart';
import 'package:kumone_flutter/core/storage/account_store.dart';
import 'package:kumone_flutter/ui/pages/library_page.dart';
import 'package:kumone_flutter/ui/widgets/auto_scroll_metadata.dart';
import 'package:kumone_flutter/ui/widgets/glass_side_navigation.dart';
import 'package:kumone_flutter/ui/widgets/glass_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/widgets/glass_controls.dart';
import 'package:kumone_flutter/ui/widgets/liquid_surface.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';
import 'package:kumone_flutter/ui/widgets/marquee_text.dart';

class _LibraryAccount extends AccountStore {
  _LibraryAccount() {
    profile = const UserProfile(userId: 1, nickname: 'Test');
  }
  @override
  bool get isLoggedIn => true;
  @override
  Future<void> refreshLibrary() async {}
}

void main() {
  testWidgets('create playlist dialog stays compact on a tablet', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _LibraryAccount();
    // Exercise the standalone add button; top navigation is hosted by AppShell.
    final settings = SettingsStore()..wideTopTabs = false;
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<AccountStore>.value(value: account),
      ChangeNotifierProvider.value(value: settings),
    ], child: const MaterialApp(home: Scaffold(body: LibraryPage()))));
    await tester.ensureVisible(find.text('创建的歌单'));
    await tester.tap(find.text('创建的歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建歌单'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final surface = find.ancestor(of: find.text('新建歌单'),
        matching: find.byType(KumoneLiquidSurface));
    expect(tester.getSize(surface).width, lessThanOrEqualTo(340));
    expect(tester.getSize(surface).height, lessThan(320));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // Avatar recovery tries four endpoints with independent 8s timeouts.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 9));
    }
    account.dispose();
    settings.dispose();
  });

  test('detail routes support native iOS transitions and player presents vertically', () {
    final detail = kumonePageRoute<void>(const SizedBox()) as CupertinoPageRoute<void>;
    final player = kumonePageRoute<void>(const SizedBox(),
        settings: const RouteSettings(name: '/now-playing')) as PageRoute<void>;
    expect(detail.fullscreenDialog, false);
    expect(player.fullscreenDialog, true);
    expect(player.opaque, false);
  });

  testWidgets('metadata row scrolls as one tappable artist and album line',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 160,
                child: Column(children: [
                  AutoScrollMetadata(
                      identity: 'song',
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                            onPressed: () {},
                            child: const Text(
                                'A very very very long artist name')),
                        TextButton(
                            onPressed: () {},
                            child:
                                const Text('A very very very long album name')),
                      ]))
                ])))));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact landscape glass navigation fits and selects',
      (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: KumoneGlassSideNavigation(
                selectedIndex: 0,
                onChanged: (i) => selected = i,
                onExpand: () {},
                labels: const [
          '推荐',
          '精选',
          '搜索',
          '我的'
        ],
                icons: const [
          Icons.home,
          Icons.grid_view,
          Icons.search,
          Icons.person
        ]))));
    await tester.tap(find.byIcon(Icons.search));
    expect(selected, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('iOS release to refresh has no visible indicator',
      (tester) async {
    var refreshed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: KumoneGlassRefresh(
                onRefresh: () async {
                  refreshed = true;
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [SizedBox(height: 1200)])))));
    final scroll = find.byType(CustomScrollView);
    final gesture = await tester.startGesture(tester.getCenter(scroll));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(refreshed, false);
    await tester.drag(scroll, const Offset(0, 650));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, true);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(KumoneLiquidSurface), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('shared blur and floating navigation settings persist', () async {
    final settings = SettingsStore();
    final opacity = settings.menuBackingOpacity;
    await settings.saveChromeBlur(37.5);
    expect(settings.lyricFontScale, 1.1);
    await settings.saveLyricFontScale(1.23);
    await settings.saveSongMenuBlur(23);
    await settings.saveQuickEntryBlur(4);
    await settings.saveSideNavigationScale(1.2);
    await settings.saveSideNavigationPosition(.3);
    await settings.saveSideNavigationExpandedPosition(.65);
    await settings.setSideNavigationOnLeft(true);
    await settings.setSideNavigationOrder([1, 0, 3]);
    final restored = SettingsStore();
    await restored.load();
    expect(restored.chromeBlur, 23);
    expect(restored.lyricFontScale, 1.23);
    restored.previewLyricFontScale(3);
    expect(restored.lyricFontScale, 1.8);
    restored.previewLyricFontScale(0);
    expect(restored.lyricFontScale, .8);
    expect(restored.songMenuBlur, 23);
    expect(restored.quickEntryBlur, 4);
    expect(restored.sideNavigationScale, 1.2);
    expect(restored.sideNavigationPosition, .3);
    expect(restored.sideNavigationExpandedPosition, .65);
    expect(restored.sideNavigationOnLeft, true);
    expect(restored.sideNavigationOrder, [1, 0, 3]);
    await restored.setSideNavigationOrder([0, 2, 3]);
    expect(restored.sideNavigationOrder, [1, 0, 3]);
    expect(restored.menuBackingOpacity, opacity);
    settings.dispose();
    restored.dispose();
  });

  testWidgets('menu and quick-entry blur are independent of each other and opacity',
      (tester) async {
    final settings = SettingsStore();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
          home: Scaffold(
              body: Consumer<SettingsStore>(
        builder: (_, settings, __) => Column(children: [
          KumoneLiquidSurface(
              key: const ValueKey('menu'),
              backingOpacity: .72,
              blur: settings.songMenuBlur,
              child: const SizedBox(width: 200, height: 50)),
          KumoneLiquidSurface(
              key: const ValueKey('quick'),
              backingOpacity: .72,
              blur: settings.quickEntryBlur,
              child: const SizedBox(width: 200, height: 50)),
        ]),
      ))),
    ));
    final surfaces = tester
        .widgetList<LiquidGlassLens>(find.byType(LiquidGlassLens))
        .toList();
    expect(surfaces[0].style.blur, 3);
    expect(surfaces[1].style.blur, 3);
    expect(surfaces[0].style.color.a, closeTo(.72, .01));
    settings.previewSongMenuBlur(31);
    settings.previewQuickEntryBlur(2);
    await tester.pump();
    final changed = tester
        .widgetList<LiquidGlassLens>(find.byType(LiquidGlassLens))
        .toList();
    expect(changed[0].style.blur, 31);
    expect(changed[1].style.blur, 2);
    expect(changed[0].style.color, surfaces[0].style.color);
    expect(settings.chromeBlur, 31);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('collapsed search expands at 200ms and selects by sliding',
      (tester) async {
    int? selected;
    final expanded = ValueNotifier(false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ValueListenableBuilder<bool>(
          valueListenable: expanded,
          builder: (_, value, __) => KumoneGlassSideNavigation(
                selectedIndex: 0,
                expanded: value,
                onExpand: () => expanded.value = true,
                onChanged: (i) => selected = i,
                labels: const ['推荐', '精选', '搜索', '我的'],
                icons: const [
                  Icons.home,
                  Icons.grid_view,
                  Icons.search,
                  Icons.person
                ],
              )),
    )));
    expect(find.text('我的'), findsNothing);
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('floating-search'))));
    await tester.pump(const Duration(milliseconds: 190));
    expect(expanded.value, false);
    await tester.pump(const Duration(milliseconds: 20));
    expect(expanded.value, true);
    // A grabbed motion pill intentionally ticks until the finger releases.
    await tester.pump(const Duration(milliseconds: 350));
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('floating-tab-1'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.byTooltip('设置'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expanded.dispose();
  });

  testWidgets(
      'floating navigation fits short windows, side, size and custom order',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(700, 300), const Size(1200, 800)]) {
      tester.view.physicalSize = size;
      for (final onLeft in [true, false]) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
          body: KumoneGlassSideNavigation(
            selectedIndex: 0,
            onChanged: (_) {},
            onExpand: () {},
            onLeft: onLeft,
            scale: 1.4,
            position: 1,
            order: const [1, 0, 3],
            labels: const ['推荐', '精选', '搜索', '我的'],
            icons: const [
              Icons.home,
              Icons.grid_view,
              Icons.search,
              Icons.person
            ],
          ),
        )));
        await tester.pumpAndSettle();
        final search =
            tester.getRect(find.byKey(const ValueKey('floating-search')));
        expect(search.left, greaterThanOrEqualTo(16));
        expect(search.right, lessThanOrEqualTo(size.width - 16));
        expect(search.top, greaterThanOrEqualTo(16));
        expect(
            tester.getRect(find.byKey(const ValueKey('floating-tab-3'))).bottom,
            lessThanOrEqualTo(size.height - 16));
        if (onLeft) {
          expect(search.center.dx, lessThan(size.width / 2));
        } else {
          expect(search.center.dx, greaterThan(size.width / 2));
        }
        expect(tester.getCenter(find.text('精选')).dy,
            lessThan(tester.getCenter(find.text('推荐')).dy));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a refresh in progress cannot trigger a second request',
      (tester) async {
    final done = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: KumoneGlassRefresh(
      onRefresh: () {
        calls++;
        return done.future;
      },
      child: ListView(children: const [SizedBox(height: 1600)]),
    ))));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 650));
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 650));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    done.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('top bar blur covers the status bar only on glass-bar pages',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 28);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(title: Text('Glass')),
      body: SizedBox(),
    )));
    final edge = find.byType(LiquidGlassScrollEdge);
    expect(tester.getTopLeft(edge).dy, 0);
    expect(tester.getSize(edge).height, kToolbarHeight + 28);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('No toolbar'))));
    expect(find.byType(LiquidGlassScrollEdge), findsNothing);
  });

  testWidgets('surface blur changes without changing tint opacity',
      (tester) async {
    final settings = SettingsStore();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(
            home: Scaffold(
                body: KumoneLiquidSurface(
                    child: SizedBox(width: 220, height: 60))))));
    final before =
        tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens)).style;
    settings.previewChromeBlur(32);
    await tester.pump();
    final after =
        tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens)).style;
    expect(after.blur, 32);
    expect(after.color, before.color);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('glass switch and search preserve callbacks', (tester) async {
    bool? changed;
    String? query;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      KumoneGlassSwitchTile(
          value: false,
          onChanged: (value) => changed = value,
          title: const Text('Toggle')),
      KumoneGlassSearchField(onChanged: (value) => query = value),
    ]))));
    expect(find.byType(LiquidGlassSwitch), findsOneWidget);
    await tester.tap(find.text('Toggle'));
    expect(changed, true);
    await tester.enterText(find.byType(TextField), 'Michael Jackson');
    expect(query, 'Michael Jackson');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pushed glass app bar uses the iOS back chevron', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(kumonePageRoute<void>(
                    const Scaffold(
                        appBar: KumoneGlassAppBar(title: Text('Detail'))),
                  )),
                  child: const Text('Open'),
                ),
              )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.chevron_back), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_back));
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('search field vertically centers text and its prefix icon',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: KumoneGlassSearchField(
          decoration: InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: '搜索此歌单',
      )),
    )));
    final glass = find.descendant(of: find.byType(KumoneGlassSearchField),
        matching: find.byType(LiquidGlassLens));
    expect(tester.getSize(glass).height, 40);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.contentPadding,
        const EdgeInsets.symmetric(vertical: 8));
    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(field.maxLines, 1);
    await tester.enterText(find.byType(TextField), '歌曲');
    await tester.pump();
    final iconCenter = tester.getCenter(find.byIcon(Icons.search));
    final textCenter = tester.getCenter(find.byType(EditableText));
    expect((iconCenter.dy - textCenter.dy).abs(), lessThanOrEqualTo(2));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(
      height: 56, child: Center(child: KumoneGlassSearchField(height: 40,
        decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索')))))));
    expect(tester.getSize(find.byType(LiquidGlassLens)).height, 40);
    expect((tester.getCenter(find.byIcon(Icons.search)).dy -
        tester.getCenter(find.byType(LiquidGlassLens)).dy).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('long app bar titles use the clipped scrolling title',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            appBar: KumoneGlassAppBar(
                title: Text(
                    'A very long playlist title that cannot possibly fit in the toolbar')),
            body: SizedBox())));
    expect(find.byType(MarqueeText), findsOneWidget);
    expect(find.byType(LiquidGlassScrollEdge), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact glass slider fits the existing 30 pixel volume row',
      (tester) async {
    double? changed;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 260,
                    height: 30,
                    child: KumoneGlassSlider(
                        compact: true,
                        value: .5,
                        onChanged: (v) => changed = v))))));
    await tester.drag(find.byType(LiquidGlassSlider), const Offset(40, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(changed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
