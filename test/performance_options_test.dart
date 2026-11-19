import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/widgets/route_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty(); });
  test('outgoing snapshot is opt-in and persists', () async {
    final store = SettingsStore();
    expect(store.freezeOutgoingPage, false);
    await store.setFreezeOutgoingPage(true);
    final restored = SettingsStore();
    await restored.load();
    expect(restored.freezeOutgoingPage, true);
    store.dispose(); restored.dispose();
  });
  testWidgets('covered page snapshots only with switch enabled and restores on return', (tester) async {
    final store = SettingsStore();
    final animation = AnimationController(vsync: tester, duration: const Duration(milliseconds: 100));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store,
      child: MaterialApp(home: KumoneRouteSnapshot(covered: animation,
        child: const ColoredBox(color: Colors.green)))));
    animation.forward();
    await tester.pumpAndSettle();
    expect(tester.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller.allowSnapshotting, false);
    await store.setFreezeOutgoingPage(true);
    await tester.pump();
    expect(tester.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller.allowSnapshotting, true);
    animation.reverse();
    await tester.pumpAndSettle();
    expect(tester.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller.allowSnapshotting, false);
    await tester.pumpWidget(const SizedBox());
    animation.dispose(); store.dispose();
  });
}
