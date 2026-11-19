import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/custom_source_store.dart';
import 'package:kumone_flutter/core/models/models.dart';
import 'package:kumone_flutter/core/unblock/unblock_service.dart';
import 'package:kumone_flutter/ui/pages/source_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
      'disabled and invalid sources are skipped; enabled candidates preserve order',
      () async {
    final store = CustomSourceStore();
    for (var i = 0; i < 4; i++) {
      await store.put(
          id: '$i',
          name: 'Source $i',
          endpoint: 'https://example.com/$i',
          enabled: i != 0);
    }
    final dio = Dio();
    final requested = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requested.add(options.uri.path);
      expect(options.queryParameters['name'], 'Song');
      expect(options.headers.containsKey('Cookie'), false);
      handler.resolve(Response(requestOptions: options, data: {
        'url': options.uri.path == '/1'
            ? 'file:///invalid.mp3'
            : 'https://example.com/audio.mp3',
      }));
    }));
    final track = Track.fromJson({
      'id': 1,
      'name': 'Song',
      'ar': [],
      'al': {'id': 1}
    });
    final results =
        await UnblockService.candidates(track, client: dio).toList();
    expect(requested, ['/1', '/2', '/3']);
    expect(results.map((e) => e.source).toList(),
        ['Custom:2:Source 2', 'Custom:3:Source 3']);
    store.dispose();
    dio.close();
  });
  testWidgets('source configuration adds a disabled source through the dialog',
      (tester) async {
    final clean = CustomSourceStore();
    await clean.load();
    for (final source in clean.sources) { await clean.remove(source.id); }
    clean.dispose();
    await tester.pumpWidget(const MaterialApp(home: SourceSettingsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('添加音源（0/7）'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('添加音源（0/7）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'My source');
    await tester.enterText(
        find.byType(TextField).at(1), 'https://example.com/resolve');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final sources = await CustomSourceStore.readSources();
    expect(sources.single.name, 'My source');
    expect(sources.single.enabled, false);
    expect(find.text('1. My source'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
