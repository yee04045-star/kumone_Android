import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/player/player_controller.dart';
import 'package:kumone_flutter/core/storage/account_store.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/pages/collections_page.dart';
import 'package:kumone_flutter/ui/pages/library_media_pages.dart';
import 'package:kumone_flutter/ui/widgets/glass_category_chip.dart';

class _UnusedPlayer extends ChangeNotifier implements PlayerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineAccount extends AccountStore {
  @override
  bool get isLoggedIn => false;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final recent in [false, true]) {
    testWidgets(
        '${recent ? 'recent history' : 'collections'} uses neutral shared categories and switches correctly',
        (tester) async {
      final account = _OfflineAccount();
      final settings = SettingsStore();
      final player = _UnusedPlayer();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final first = recent ? '所有时间' : '专辑';
      final second = recent ? '最近一周' : '歌手';
      for (final brightness in Brightness.values) {
        for (final width in [360.0, 800.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpWidget(MultiProvider(
              providers: <SingleChildWidget> [
                ChangeNotifierProvider<AccountStore>.value(value: account),
                ChangeNotifierProvider.value(value: settings),
                ChangeNotifierProvider<PlayerController>.value(value: player),
              ],
              child: MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: recent ? const RecentPage() : const CollectionsPage(),
              )));
          await tester.pumpAndSettle();
          expect(find.byType(GlassCategoryChip), findsNWidgets(2));
          expect(find.byType(SegmentedButton<int>), findsNothing);
          expect(find.byType(SegmentedButton<bool>), findsNothing);
          expect(find.byIcon(Icons.check), findsNothing);
          final text = tester.widget<Text>(find.text(second));
          expect(
              text.style!.color,
              Theme.of(tester.element(find.text(second)))
                  .colorScheme
                  .onSurface);
          await tester.tap(find.text(second));
          await tester.pumpAndSettle();
          final chips = tester
              .widgetList<GlassCategoryChip>(find.byType(GlassCategoryChip))
              .toList();
          expect(chips.first.selected, false);
          expect(chips.last.selected, true);
          await tester.tap(find.text(first));
          await tester.pumpAndSettle();
          expect(
              tester
                  .widgetList<GlassCategoryChip>(find.byType(GlassCategoryChip))
                  .first
                  .selected,
              true);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
      account.dispose();
      settings.dispose();
      player.dispose();
    });
  }
}
