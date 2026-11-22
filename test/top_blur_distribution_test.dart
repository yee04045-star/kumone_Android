import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';
import 'package:kumone_flutter/ui/widgets/top_blur_distribution.dart';

void main() {
  testWidgets('top blur tint and feather reach zero before the clip boundary', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox(height: 120,
      child: LiquidGlassScrollEdge(edge: LiquidGlassEdge.top, blur: 26,
        color: Color(0x33FFFFFF)))));
    final gradients = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((box) => box.gradient)
      .whereType<LinearGradient>().toList();
    expect(gradients.length, greaterThanOrEqualTo(2));
    for (final gradient in gradients) {
      expect(gradient.stops![gradient.stops!.length - 2], .94);
      expect(gradient.stops!.last, 1);
      expect(gradient.colors[gradient.colors.length - 2].a, 0);
      expect(gradient.colors.last.a, 0);
    }
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('distribution is smooth, monotonic, and keeps both endpoints', () {
    for (final strength in [.5, 1.0, 2.0, 4.0, 6.0]) {
      final curve = KumoneTopBlurDistribution(strength);
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      var previous = 0.0;
      for (var i = 1; i <= 100; i++) {
        final current = curve.transform(i / 100);
        expect(current, greaterThanOrEqualTo(previous));
        expect(current, inInclusiveRange(0, 1));
        previous = current;
      }
    }
    for (final t in [.1, .25, .5, .75, .9]) {
      expect(const KumoneTopBlurDistribution(1).transform(t),
          closeTo(Curves.easeInOut.transform(t), .0001));
      expect(const KumoneTopBlurDistribution(4).transform(t),
          lessThan(const KumoneTopBlurDistribution(1).transform(t)));
    }
  });

  test('distribution persists, clamps and restores without changing optics',
      () async {
    final settings = SettingsStore();
    expect(settings.topBlurDistribution, 1.20);
    expect(settings.topBlurExtent, 1.20);
    await settings.saveTopBlurDistribution(3.75);
    final restored = SettingsStore();
    await restored.load();
    expect(restored.topBlurDistribution, 3.75);
    expect(restored.chromeBlur, 3);
    expect(restored.menuBackingOpacity, .50);
    restored.previewTopBlurDistribution(100);
    expect(restored.topBlurDistribution, 6);
    restored.previewTopBlurDistribution(-1);
    expect(restored.topBlurDistribution, .5);
    await restored.saveTopBlurDistribution(1);
    settings.dispose();
    restored.dispose();
  });

  testWidgets('top gradient updates live without changing tint sigma or bounds',
      (tester) async {
    final settings = SettingsStore();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(
          home: Scaffold(
              appBar: KumoneGlassAppBar(title: Text('每日推荐')),
              body: SizedBox())),
    ));
    final finder = find.byType(LiquidGlassScrollEdge);
    final before = tester.widget<LiquidGlassScrollEdge>(finder);
    final size = tester.getSize(finder);
    settings.previewTopBlurDistribution(4);
    await tester.pump();
    final after = tester.widget<LiquidGlassScrollEdge>(finder);
    expect(after.blurCurve.transform(.5),
        lessThan(before.blurCurve.transform(.5)));
    expect(after.blur, before.blur);
    expect(after.color, before.color);
    expect(after.curve, before.curve);
    expect(tester.getSize(finder), size);
    settings.previewTopBlurExtent(2);
    await tester.pump();
    expect(tester.getSize(finder).height, closeTo(size.height / 1.2 * 2, .001));
    expect(tester.getTopLeft(finder).dy, 0);
    expect(tester.getSize(find.byType(AppBar)).height, closeTo(size.height / 1.2, .001));
    await settings.saveTopBlurExtent(2.3);
    final restored = SettingsStore();
    await restored.load();
    expect(restored.topBlurExtent, 2.3);
    restored.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
