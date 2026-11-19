import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomSource {
  final String id, name, endpoint;
  final bool enabled;
  const CustomSource(
      {required this.id,
      required this.name,
      required this.endpoint,
      this.enabled = false});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'endpoint': endpoint, 'enabled': enabled};
  factory CustomSource.fromJson(Map<String, dynamic> json) => CustomSource(
      id: json['id'] as String,
      name: json['name'] as String,
      endpoint: json['endpoint'] as String,
      enabled: json['enabled'] == true);
}

class CustomSourceStore extends ChangeNotifier {
  static const maxSources = 7;
  static final _prefs = SharedPreferencesAsync();
  List<CustomSource> _sources = [];
  List<CustomSource> get sources => List.unmodifiable(_sources);
  static void validate(String name, String endpoint) {
    final uri = Uri.tryParse(endpoint.trim());
    if (name.trim().isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('请填写名称和有效的 HTTPS 解析接口地址（不可包含账号密码或片段）');
    }
  }

  static Future<List<CustomSource>> readSources() async {
    final raw = await _prefs.getString('customAudioSources');
    if (raw == null) return [];
    try {
      final result = <CustomSource>[];
      for (final item in (jsonDecode(raw) as List).take(maxSources)) {
        try {
          final source =
              CustomSource.fromJson(Map<String, dynamic>.from(item as Map));
          validate(source.name, source.endpoint);
          result.add(source);
        } catch (_) {}
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<void> load() async {
    _sources = await readSources();
    notifyListeners();
  }

  Future<void> _save(List<CustomSource> next) async {
    await _prefs.setString(
        'customAudioSources', jsonEncode(next.map((e) => e.toJson()).toList()));
    _sources = next;
    notifyListeners();
  }

  Future<void> put(
      {String? id,
      required String name,
      required String endpoint,
      bool enabled = false}) async {
    validate(name, endpoint);
    final next = List<CustomSource>.of(_sources);
    final index = next.indexWhere((e) => e.id == id);
    if (index < 0 && next.length >= maxSources) {
      throw const FormatException('最多添加 7 个音源');
    }
    final source = CustomSource(
        id: id ?? '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}',
        name: name.trim(),
        endpoint: endpoint.trim(),
        enabled: enabled);
    if (index < 0) {
      next.add(source);
    } else {
      next[index] = source;
    }
    await _save(next);
  }

  Future<void> remove(String id) =>
      _save(_sources.where((e) => e.id != id).toList());
  Future<void> move(int index, int delta) async {
    final target = index + delta;
    if (index < 0 ||
        index >= _sources.length ||
        target < 0 ||
        target >= _sources.length) {
      return;
    }
    final next = List<CustomSource>.of(_sources);
    next.insert(target, next.removeAt(index));
    await _save(next);
  }
}
