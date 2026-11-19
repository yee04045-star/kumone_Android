import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/models/models.dart';
import 'package:kumone_flutter/core/storage/account_store.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/core/storage/wallpaper_store.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';

void main() {
  setUp(() { SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty(); });
  test('wallpaper directions never crop a portrait image into landscape', () {
    final store = WallpaperStore()..path = 'portrait.png'..dark = true;
    expect(store.pathFor(false), 'portrait.png');
    expect(store.pathFor(true), null);
    store.landscapePath = 'landscape.png';
    store.landscapeDark = false;
    expect(store.pathFor(true), 'landscape.png');
    expect(store.darkFor(true), false);
    expect(store.darkFor(false), true);
    store.dispose();
  });
  test('song menu focus defaults on and persists off', () async {
    final settings = SettingsStore();
    expect(settings.songMenuFocus, true);
    await settings.setSongMenuFocus(false);
    final restored = SettingsStore();
    await restored.load();
    expect(restored.songMenuFocus, false);
    settings.dispose(); restored.dispose();
  });
  testWidgets('transparent search-style row has its own material and press feedback', (tester) async {
    final settings = SettingsStore();
    final account = AccountStore();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: account),
    ], child: MaterialApp(home: Scaffold(backgroundColor: Colors.transparent,
      body: TrackActionMenu(showButton: false,
        track: Track.fromJson({'id': 1, 'name': 'Test', 'ar': [], 'al': {'id': 1}}),
        child: ListTile(title: const Text('Test song'), onTap: () {})),
    ))));
    final row = find.byType(TrackActionMenu);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Test song')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(find.descendant(of: row,
      matching: find.byType(AnimatedScale))).scale, .985);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('下一首播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    settings.dispose(); account.dispose();
  });
}
