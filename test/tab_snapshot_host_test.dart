import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/widgets/tab_snapshot_host.dart';

void main() {
  testWidgets('tab selected under details stays live during return', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final selected = ValueNotifier(0);
    final settings = SettingsStore();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: settings,
      child: MaterialApp(navigatorKey: navigator,
        home: KumoneTabSnapshotHost(selected: selected, pages: [
          for (var i = 0; i < 4; i++) _Page(index: i, created: () {}),
        ]))));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Detail'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    List<SnapshotWidget> snapshots() => tester.widgetList<SnapshotWidget>(
      find.byType(SnapshotWidget, skipOffstage: false)).toList();
    expect(snapshots().where((w) => w.controller.allowSnapshotting).length, 1);
    selected.value = 3;
    await tester.pump();
    expect(snapshots().every((w) => !w.controller.allowSnapshotting), isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Tab 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    selected.dispose(); settings.dispose();
  });
  testWidgets('warmup does not change selection or recreate tab states', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final selected = ValueNotifier(0);
    final settings = SettingsStore();
    var creates = 0;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: settings,
      child: MaterialApp(home: KumoneTabSnapshotHost(selected: selected, pages: [
        for (var i = 0; i < 4; i++) _Page(index: i, created: () => creates++),
      ]))));
    expect(creates, 4);
    expect(find.text('Tab 0'), findsOneWidget);
    // Real async rendering is required for texture-backed toImage operations.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 270)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(selected.value, 0);
      expect(find.text('Tab 0'), findsOneWidget);
      expect(creates, 4);
    }
    selected.value = 2;
    await tester.pump();
    expect(find.text('Tab 2'), findsOneWidget);
    expect(creates, 4);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    selected.dispose(); settings.dispose();
    expect(tester.takeException(), isNull);
  });
}
class _Page extends StatefulWidget {
  final int index;
  final VoidCallback created;
  const _Page({required this.index, required this.created});
  @override
  State<_Page> createState() => _PageState();
}
class _PageState extends State<_Page> {
  @override
  void initState() { super.initState(); widget.created(); }
  @override
  Widget build(BuildContext context) => Scaffold(body: Text('Tab ${widget.index}'));
}
