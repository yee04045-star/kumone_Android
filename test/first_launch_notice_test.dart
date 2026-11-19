import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/ui/widgets/first_launch_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets(
      'confirmation persists across app rebuilds and suppresses the notice',
      (tester) async {
    Widget app() => MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => FirstLaunchNotice.showIfNeeded(context),
                    child: const Text('Launch')))));
    await tester.pumpWidget(app());
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(find.text('使用提示'), findsOneWidget);
    expect(await FirstLaunchNotice.acknowledged, false);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('使用提示'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('使用提示'), findsNothing);
    expect(await FirstLaunchNotice.acknowledged, true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(find.text('使用提示'), findsNothing);
  });
}
