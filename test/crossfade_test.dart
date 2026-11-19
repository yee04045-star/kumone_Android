import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/core/player/crossfade_curve.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('equal-power overlap has correct endpoints and constant energy', () {
    expect(crossfadeGains(0, .8).$1, closeTo(.8, 1e-9));
    expect(crossfadeGains(0, .8).$2, 0);
    expect(crossfadeGains(1, .8).$1, closeTo(0, 1e-9));
    expect(crossfadeGains(1, .8).$2, closeTo(.8, 1e-9));
    for (var i = 0; i <= 100; i++) {
      final (a, b) = crossfadeGains(i / 100, .8);
      expect(a * a + b * b, closeTo(.64, 1e-9));
    }
  });
  test('continuous slider saves nearest integer within zero to twelve',
      () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = SettingsStore();
    await settings.saveCrossfade(4.6);
    expect(settings.crossfadeSeconds, 5);
    final reload = SettingsStore();
    await reload.load();
    expect(reload.crossfadeSeconds, 5);
    settings.previewCrossfade(15);
    expect(settings.crossfadeSeconds, 12);
    settings.previewCrossfade(-1);
    expect(settings.crossfadeSeconds, 0);
    settings.dispose();
    reload.dispose();
  });
}
