import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/models/models.dart';
import 'package:kumone_flutter/core/models/lyrics.dart';
import 'package:kumone_flutter/core/player/player_controller.dart';
import 'package:kumone_flutter/core/storage/account_store.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/pages/now_playing_page.dart';

const track = Track(id: 1, name: 'Song', artists: [ArtistRef(id: 1, name: 'Artist')],
  album: AlbumRef(id: 1, name: 'Album'), durationMs: 180000);
class TestPlayer extends ChangeNotifier implements PlayerController {
  Duration? lastSeek;
  @override Future<void> seek(Duration target) async { lastSeek = target; playbackPosition = target; }
  @override Track get currentTrack => track;
  Duration playbackPosition = Duration.zero;
  @override Duration get position => playbackPosition;
  @override Duration get duration => const Duration(minutes: 3);
  @override double get volume => .5;
  @override bool get isPlaying => false;
  @override bool get shuffle => false;
  @override AudioServiceRepeatMode get repeatMode => AudioServiceRepeatMode.none;
  @override IconData get playbackModeIcon => Icons.repeat;
  @override String get playbackModeLabel => '顺序播放';
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  testWidgets('preview first row stays top aligned for two and three rows', (tester) async {
    final player = TestPlayer();
    const lyrics = ParsedLyrics([
      LyricLine(startMs: 0, text: 'Line A'),
      LyricLine(startMs: 1000, text: 'Line B'),
      LyricLine(startMs: 2000, text: 'Line C'),
    ]);
    Future<void> show() => tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: SettingsStore()),
      ChangeNotifierProvider.value(value: AccountStore()),
      ChangeNotifierProvider<PlayerController>.value(value: player),
    ], child: MaterialApp(home: Scaffold(body: kumonePlayerPortraitForTest(
      track: track, player: player, lyrics: lyrics)))));
    await show();
    await tester.pump();
    final firstTop = tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('portrait-preview')), matching: find.text('Line A'))).dy;
    player.playbackPosition = const Duration(milliseconds: 1500);
    await show();
    await tester.pump();
    expect(tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('portrait-preview')), matching: find.text('Line A'))).dy, closeTo(firstTop, .01));
    expect(find.descendant(of: find.byKey(const ValueKey('portrait-preview')), matching: find.text('Line C')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
  test('removed switches load enabled despite old saved off values', () async {
    final settings = SettingsStore();
    for (final key in ['ambient', 'freezeOutgoingPage', 'backgroundExtend',
      'landscapeDualPane', 'songMenuFocus']) {
      await settings.prefs.setBool(key, false);
    }
    await settings.prefs.setString('nowPlaying', 'vinyl');
    await settings.load();
    expect([settings.ambient, settings.freezeOutgoingPage, settings.backgroundExtend,
      settings.landscapeDualPane, settings.songMenuFocus], everyElement(isTrue));
    expect(settings.nowPlaying, NowPlayingMode.immersive);
  });
  for (final size in [const Size(360, 640), const Size(393, 800), const Size(430, 920)]) {
    for (final minimal in [false, true]) {
      testWidgets('portrait $size minimal=$minimal fits with thumb-free sliders', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final player = TestPlayer();
        var closed = false;
        await tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider.value(value: SettingsStore()),
          ChangeNotifierProvider.value(value: AccountStore()),
          ChangeNotifierProvider<PlayerController>.value(value: player),
        ], child: MaterialApp(home: Scaffold(body: kumonePlayerPortraitForTest(
          track: track, player: player, minimal: minimal, onClose: () => closed = true)))));
        expect(tester.takeException(), isNull);
        expect(find.byType(Slider), findsNWidgets(2));
        for (final slider in tester.elementList(find.byType(Slider))) {
          expect(SliderTheme.of(slider).thumbShape, SliderComponentShape.noThumb);
        }
        final timeline = find.byType(Slider).first;
        final rect = tester.getRect(timeline);
        await tester.dragFrom(Offset(rect.left + 8, rect.center.dy),
            Offset(rect.width * .6, 0));
        await tester.pump();
        expect(player.lastSeek, isNotNull);
        expect(player.lastSeek!.inSeconds, greaterThan(60));
        await tester.drag(find.bySemanticsLabel('下拉关闭播放页'), const Offset(0, 70));
        await tester.pump();
        expect(closed, true);
        await tester.pumpWidget(const SizedBox());
        player.dispose();
      });
    }
  }
}
