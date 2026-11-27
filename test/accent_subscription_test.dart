import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/core/api/netease_api.dart';
import 'package:kumone_flutter/core/api/netease_client.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/theme/app_theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('saved accents reload with retired NetEase red migrated to Apple red',
      () async {
    for (final accent in AppAccent.values) {
      final settings = SettingsStore();
      await settings.setAccent(accent);
      final restored = SettingsStore();
      await restored.load();
      expect(restored.accent, accent == AppAccent.neteaseRed ? AppAccent.appleRed : accent);
      expect(KumoneTheme.light(color: accent.color).colorScheme.primary,
          accent.color);
      expect(KumoneTheme.dark(color: accent.color).colorScheme.primary,
          accent.color);
      settings.dispose();
      restored.dispose();
    }
    for (final dark in [false, true]) {
      final base = dark ? KumoneTheme.dark() : KumoneTheme.light();
      for (final accent in AppAccent.values) {
        final theme = dark ? KumoneTheme.dark(color: accent.color)
            : KumoneTheme.light(color: accent.color);
        expect(theme.colorScheme.surface, base.colorScheme.surface);
        expect(theme.colorScheme.onSurface, base.colorScheme.onSurface);
        expect(theme.colorScheme.onSurfaceVariant, base.colorScheme.onSurfaceVariant);
        expect(theme.colorScheme.surfaceContainer, base.colorScheme.surfaceContainer);
        expect(theme.textTheme.bodyMedium?.color, base.textTheme.bodyMedium?.color);
      }
    }
    expect(AppAccent.neteaseRed.color.toARGB32(), 0xFFC3473B);
    expect(AppAccent.spotifyGreen.color.toARGB32(), 0xFF65D46E);
    expect(AppAccent.appleBlue.color, KumoneTheme.systemBlue);
    expect(AppAccent.values.map((e) => e.color).toSet().length, 5);
  });

  test(
      'artist writes use original plain form; playlist writes use desktop EAPI',
      () async {
    final client = NeteaseClient.instance;
    await client.setCookies({'MUSIC_U': 'test-session', '__csrf': 'test-csrf'});
    final requests = <RequestOptions>[];
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(requestOptions: options, data: {'code': 200}));
    });
    client.dio.interceptors.add(interceptor);
    addTearDown(() => client.dio.interceptors.remove(interceptor));
    for (final subscribe in [true, false]) {
      await NeteaseApi.instance.subscribeArtist(123, subscribe);
      final artist = requests.last;
      expect(artist.uri.path, '/api/artist/${subscribe ? 'sub' : 'unsub'}');
      expect(artist.method, 'POST');
      expect(artist.data, {'artistId': '123', 'artistIds': '[123]'});
      expect(artist.headers['Cookie'], contains('MUSIC_U=test-session'));
      await NeteaseApi.instance.subscribePlaylist(456, subscribe);
      final playlist = requests.last;
      expect(playlist.uri.host, 'interface.music.163.com');
      expect(playlist.uri.path,
          '/eapi/playlist/${subscribe ? 'subscribe' : 'unsubscribe'}');
      expect(playlist.data, contains('params'));
      expect(playlist.headers['Cookie'], contains('os=pc'));
    }
    expect(requests.length, 4);
  });

  test('artist business failure propagates instead of reporting success',
      () async {
    final client = NeteaseClient.instance;
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options, data: {'code': 301, 'message': '需要登录'}));
    });
    client.dio.interceptors.add(interceptor);
    addTearDown(() => client.dio.interceptors.remove(interceptor));
    await expectLater(NeteaseApi.instance.subscribeArtist(123, true),
        throwsA(isA<NeteaseException>()));
  });
}
