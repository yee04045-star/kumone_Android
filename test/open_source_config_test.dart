import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:kumone_flutter/core/storage/custom_source_store.dart';
import 'package:kumone_flutter/core/storage/app_icon_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('sources start empty; limit, order, enable, edit and delete persist',
      () async {
    final store = CustomSourceStore();
    await store.load();
    expect(store.sources, isEmpty);
    for (var i = 0; i < 7; i++) {
      await store.put(name: 'Source $i', endpoint: 'https://example.com/$i');
    }
    expect(store.sources.every((e) => !e.enabled), true);
    await expectLater(
        store.put(name: 'Overflow', endpoint: 'https://example.com/8'),
        throwsFormatException);
    final last = store.sources.last;
    await store.move(6, -1);
    await store.put(
        id: last.id, name: 'Edited', endpoint: last.endpoint, enabled: true);
    final restored = await CustomSourceStore.readSources();
    expect(restored[5].name, 'Edited');
    expect(restored[5].enabled, true);
    await store.remove(last.id);
    expect((await CustomSourceStore.readSources()).length, 6);
    store.dispose();
  });
  test('invalid source endpoints are rejected', () {
    for (final url in [
      'http://example.com',
      'file:///test',
      'https://user:pass@example.com',
      'https://example.com/#x',
      ''
    ]) {
      expect(
          () => CustomSourceStore.validate('Name', url), throwsFormatException);
    }
  });
  test('only nine regular icons remain in requested order', () {
    expect(AppIconChoice.values.map((e) => e.label).toList(), [
      '冰霜玻璃',
      '蓝色晶透',
      '蓝色水晶',
      '晶透红粉',
      '粉彩玻璃',
      '红粉玻璃',
      '粉色玻璃',
      '粉色水晶',
      '翡翠水晶',
    ]);
    final icons = AppIconStore();
    expect(icons.visibleChoices.length, 9);
    icons.dispose();
  });
}
