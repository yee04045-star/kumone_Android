import 'dart:async';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:kumone_flutter/core/storage/app_icon_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:kumone_flutter/core/api/netease_api.dart';
import 'package:kumone_flutter/core/api/netease_client.dart';
import 'package:kumone_flutter/core/models/models.dart';
import 'package:kumone_flutter/core/storage/account_store.dart';
import 'package:kumone_flutter/core/storage/settings_store.dart';
import 'package:kumone_flutter/ui/widgets/common.dart';
import 'package:kumone_flutter/ui/widgets/liquid_surface.dart';

Map<String, dynamic> decodeEapi(RequestOptions request) {
  final hex = (request.data as Map)['params'] as String;
  final bytes = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
  cipher.init(
      false,
      PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(Uint8List.fromList(utf8.encode('e82ckenh8dichen8'))),
          null));
  final parts = utf8.decode(cipher.process(bytes)).split('-36cd479b6b5-');
  expect(parts.first, '/api/radio/like');
  return jsonDecode(parts[1]) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = NeteaseClient.instance;

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    await client.setCookies({'MUSIC_U': 'test-session', '__csrf': 'test-csrf'});
    // Deterministic shader-free rendering for widget tests only.
    LiquidGlassEngine.liteGlassOnSkia = true;
    LiquidGlassEngine.liteGlassOnImpeller = true;
  });

  tearDown(() => client.dio.interceptors.clear());

  test('heart uses EAPI with string fields and coherent desktop cookies',
      () async {
    RequestOptions? captured;
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      captured = request;
      handler.resolve(Response(requestOptions: request, data: {'code': 200}));
    }));
    await NeteaseApi.instance.likeTrack(123, true);
    expect(captured!.uri.path, '/eapi/radio/like');
    final body = decodeEapi(captured!);
    expect(body['trackId'], '123');
    expect(body['like'], 'true');
    expect(body['alg'], 'itembased');
    expect(body['time'], '3');
    expect(body['e_r'], false);
    final header = body['header'] as Map;
    expect(header['MUSIC_U'], 'test-session');
    expect(header['deviceId'], isNot('kumone'));
    expect(captured!.headers['Cookie'],
        contains('deviceId=${header['deviceId']}'));
    expect(captured!.headers['Cookie'], contains('appver=${header['appver']}'));
  });

  test('rapid heart presses are serialized and failed write rolls back',
      () async {
    final gate = Completer<void>();
    var requests = 0;
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests++;
      await gate.future;
      handler.resolve(Response(
          requestOptions: request,
          data: {'code': 405, 'message': 'test rejection'}));
    }));
    final account = AccountStore();
    account.acceptLoginProfile(
        UserProfile.fromJson({'userId': 1, 'nickname': 'test'}));
    final first = account.toggleLike(123);
    final check = expectLater(first, throwsA(isA<NeteaseException>()));
    await account.toggleLike(123);
    expect(account.liked(123), true);
    gate.complete();
    await check;
    expect(requests, 1);
    expect(account.liked(123), false);
    account.dispose();
  });

  test('retired icon selection falls back to red', () async {
    final icons = AppIconStore();
    expect(icons.selected, AppIconChoice.red);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppIconStore.channel, (call) async {
      if (call.method == 'getIcon') return 'pink';
      return null;
    });
    await icons.load();
    expect(icons.selected, AppIconChoice.red);
    expect(icons.selected.label, '红');
    expect(icons.visibleChoices.map((e) => e.name), ['red']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppIconStore.channel, null);
    icons.dispose();
  });

  testWidgets('long press menu has glass, no comments, and back dismisses it',
      (tester) async {
    final account = AccountStore();
    final settings = SettingsStore();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Center(
                    child: TrackActionMenu(
          track: Track.fromJson({
            'id': 1,
            'name': 'Test',
            'ar': [],
            'al': {'id': 1}
          }),
          showButton: false,
          child: const SizedBox(width: 240, height: 56, child: Text('Song')),
        ))))));
    await tester.longPress(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.text('歌曲评论'), findsNothing);
    expect(find.byType(KumoneLiquidSurface), findsOneWidget);
    settings.previewMenuBackingOpacity(.25);
    await tester.pump();
    expect(
        tester
            .widget<KumoneLiquidSurface>(find.byType(KumoneLiquidSurface))
            .backingOpacity,
        .25);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    settings.dispose();
  });

  test('chrome optics keep the tab bar aligned with the mini player', () {
    // The bar's stock look is a heavy, 68%-opaque white wash — the flat
    // backing layer the tab bar used to show.
    expect(LiquidGlassTabBar.defaultStyle.color, const Color(0xADFFFFFF));

    final light = KumoneGlassOptics.applyTo(
      LiquidGlassTabBar.defaultStyle,
      Brightness.light,
    );
    // Same optical recipe as the mini player...
    expect(light.color, KumoneGlassOptics.backingColor(Brightness.light));
    expect(light.color.a, closeTo(.24, .001));
    expect(light.blur, KumoneGlassOptics.blur);
    expect(light.saturation, KumoneGlassOptics.saturation);
    expect(light.refractionIndex, KumoneGlassOptics.refractionIndex);
    expect(light.refractionWidth, KumoneGlassOptics.refractionWidth);
    expect(light.magnification, KumoneGlassOptics.magnification);
    expect(light.dispersion, KumoneGlassOptics.dispersion);
    // ...while keeping the bar's own shape, highlights and contact shadow.
    expect(light.shape, LiquidGlassTabBar.defaultStyle.shape);
    expect(light.specular, LiquidGlassTabBar.defaultStyle.specular);
    expect(light.shadow, LiquidGlassTabBar.defaultStyle.shadow);

    final dark = KumoneGlassOptics.applyTo(
      LiquidGlassTabBar.defaultDarkStyle,
      Brightness.dark,
    );
    expect(dark.color, KumoneGlassOptics.backingColor(Brightness.dark));
    expect(dark.color.a, closeTo(.30, .001));
  });

  testWidgets('mini player glass uses the shared chrome optics', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: KumoneLiquidSurface(child: SizedBox(width: 200, height: 60)),
      ),
    ));
    final lens = tester.widget<LiquidGlassLens>(find.byType(LiquidGlassLens));
    expect(lens.style.color, KumoneGlassOptics.backingColor(Brightness.light));
    expect(lens.style.blur, KumoneGlassOptics.blur);
    expect(lens.style.saturation, KumoneGlassOptics.saturation);
  });
}
