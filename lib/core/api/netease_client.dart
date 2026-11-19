import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../storage/secure_store.dart';
import 'netease_crypto.dart';

class NeteaseException implements Exception {
  final String message;
  final int? code;
  const NeteaseException(this.message, [this.code]);
  @override
  String toString() => message;
}

/// NetEase transport layer. The request shape intentionally mirrors the
/// original Kumone iOS implementation: explicit cookie jar, `os/appver`
/// defaults, CSRF propagation and response Set-Cookie absorption.
class NeteaseClient {
  NeteaseClient._();
  static final NeteaseClient instance = NeteaseClient._();

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0.0.0 Safari/537.36';

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': _userAgent,
        'Referer': 'https://music.163.com',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    ),
  );

  final Map<String, String> _cookies = {};
  bool _loaded = false;
  bool _guestEnsured = false;

  Future<void> _ensureCookies() async {
    if (_loaded) return;
    _cookies
      ..clear()
      ..addAll(await SecureStore.readCookies());
    _loaded = true;
  }

  Future<void> ensureReady() => _ensureCookies();

  bool get isLoggedIn => _cookies['MUSIC_U']?.trim().isNotEmpty == true;

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  Future<void> setCookies(Map<String, String> incoming) async {
    await _ensureCookies();
    var changed = false;
    incoming.forEach((key, value) {
      final k = key.trim();
      final v = value.trim();
      if (k.isEmpty || v.isEmpty || v == '""') return;
      if (_cookies[k] != v) {
        _cookies[k] = v;
        changed = true;
      }
    });
    if (changed) {
      await SecureStore.writeCookies(_cookies);
    }
  }

  Future<void> clearAuth() async {
    await _ensureCookies();
    _cookies.remove('MUSIC_U');
    _cookies.remove('__csrf');
    await SecureStore.writeCookies(_cookies);
  }

  /// Accepts the raw cookie string occasionally returned by QR login.
  /// Supports both `;;`-joined cookie pairs used by older NetEase responses
  /// and a normal `Cookie`/`Set-Cookie` style semicolon-delimited string.
  Future<void> ingestCookieString(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    final parsed = <String, String>{};
    const ignored = {
      'path',
      'domain',
      'expires',
      'max-age',
      'samesite',
      'secure',
      'httponly',
    };

    for (final part in text.split(RegExp(r';+'))) {
      final pair = part.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (key.isEmpty || value.isEmpty || ignored.contains(key.toLowerCase())) {
        continue;
      }
      parsed[key] = value;
    }
    if (parsed.isNotEmpty) {
      await setCookies(parsed);
    }
  }

  Future<void> ensureGuestSession() async {
    await _ensureCookies();
    if (_guestEnsured || isLoggedIn) return;
    try {
      // NetEase exposes an anonymous registration endpoint specifically for
      // public pages. It supplies a lightweight guest session and avoids some
      // unlogged 301/400 responses, while never creating a user account.
      await plainGet('/register/anonimous');
      _guestEnsured = true;
    } catch (_) {
      // Keep the flag false so a later public request may retry the guest
      // handshake instead of permanently treating a transient failure as done.
      _guestEnsured = false;
    }
  }

  Future<void> refreshQrCookies(String key) async {
    // Compatibility recovery for clients/proxies that hide Set-Cookie on the
    // first QR 803 response. The normal path remains /weapi/... exactly like
    // Kumone iOS; this performs one extra request only when MUSIC_U is absent.
    await _ensureCookies();
    if (isLoggedIn) return;
    try {
      final r = await dio.get(
        'https://music.163.com/api/login/qr/check',
        queryParameters: {
          'key': key,
          '_': DateTime.now().millisecondsSinceEpoch,
        },
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status >= 200 && status < 500,
          headers: {
            'Cookie': _cookieHeader(),
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
      await _absorbSetCookies(r.headers);
      if (r.data is Map) {
        final body = Map<String, dynamic>.from(r.data as Map);
        final cookie = body['cookie'];
        if (cookie is String && cookie.trim().isNotEmpty) {
          await ingestCookieString(cookie);
        }
        final nested = body['data'];
        if (nested is Map) {
          final nestedCookie = nested['cookie'];
          if (nestedCookie is String && nestedCookie.trim().isNotEmpty) {
            await ingestCookieString(nestedCookie);
          }
        }
      }
    } catch (_) {
      // Recovery only; the primary QR session remains authoritative.
    }
  }

  Map<String, String> _effectiveCookies({Map<String, String>? overrides}) {
    final merged = <String, String>{
      'os': 'pc',
      'appver': '3.1.17',
      ..._cookies,
      ...?overrides,
    };
    return merged;
  }

  String _cookieHeader({Map<String, String>? overrides, bool includeAuthCookies = true}) {
    final merged = includeAuthCookies
        ? _effectiveCookies(overrides: overrides)
        : <String, String>{
            'os': 'pc',
            'appver': '3.1.17',
            ...?overrides,
          };
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> _absorbSetCookies(Headers h) async {
    // Dio exposes repeated Set-Cookie headers as a list, but some proxies
    // collapse them into a single comma-separated field. We therefore parse
    // both forms and ignore cookie attributes such as Path/Expires/Secure.
    final fields = <String>[];
    for (final entry in h.map.entries) {
      if (entry.key.toLowerCase() != 'set-cookie') continue;
      fields.addAll(entry.value);
    }
    if (fields.isEmpty) return;

    const ignored = <String>{
      'path', 'domain', 'expires', 'max-age', 'samesite', 'secure',
      'httponly', 'priority', 'partitioned',
    };
    final parsed = <String, String>{};
    final cookieStart = RegExp(
      r"""(?:^|,)\s*([!#$%&'*+.^_`|~0-9A-Za-z-]+)=""",
    );

    for (final line in fields) {
      // Split at cookie-name boundaries first so an Expires date containing
      // commas does not swallow the following cookie.
      final matches = cookieStart.allMatches(line).toList();
      if (matches.isEmpty) {
        final first = line.split(';').first.trim();
        final idx = first.indexOf('=');
        if (idx > 0) {
          final key = first.substring(0, idx).trim();
          final value = first.substring(idx + 1).trim();
          if (key.isNotEmpty && !ignored.contains(key.toLowerCase()) &&
              value.isNotEmpty && value != '""') {
            parsed[key] = value;
          }
        }
        continue;
      }

      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        final key = m.group(1)!.trim();
        if (ignored.contains(key.toLowerCase())) continue;
        final valueStart = m.end;
        var valueEnd = line.length;
        final semicolon = line.indexOf(';', valueStart);
        if (semicolon >= 0) valueEnd = semicolon;
        final nextMatch = i + 1 < matches.length ? matches[i + 1].start : -1;
        if (nextMatch > valueStart && nextMatch < valueEnd) valueEnd = nextMatch;
        final value = line.substring(valueStart, valueEnd).trim();
        if (key.isNotEmpty && value.isNotEmpty && value != '""') {
          parsed[key] = value;
        }
      }
    }

    if (parsed.isNotEmpty) {
      // Crucial for QR login: the next request must see MUSIC_U immediately,
      // not after an un-awaited persistence task.
      await setCookies(parsed);
    }
  }

  String _weapiUrl(String path, Map<String, String>? overrides) {
    final csrf = (overrides?['__csrf'] ?? _cookies['__csrf'] ?? '').trim();
    if (csrf.isEmpty || path.contains('csrf_token=')) {
      return 'https://music.163.com/weapi$path';
    }
    return 'https://music.163.com/weapi$path${path.contains('?') ? '&' : '?'}csrf_token=$csrf';
  }

  Future<Map<String, dynamic>> publicWeapi(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    return _requestEncrypted(
      url: _weapiUrl(path, null),
      form: NeteaseCrypto.weapi({...payload, 'csrf_token': ''}),
      cookieOverrides: null,
      checkBusinessCode: true,
      includeAuthCookies: false,
    );
  }

  Future<Map<String, dynamic>> weapi(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, String>? cookieOverrides,
  ]) async {
    return _requestEncrypted(
      url: _weapiUrl(path, cookieOverrides),
      form: NeteaseCrypto.weapi(_withCsrf(payload, cookieOverrides)),
      cookieOverrides: cookieOverrides,
      checkBusinessCode: true,
      includeAuthCookies: true,
    );
  }

  /// Same transport as [weapi], but exposes 801/802/803 QR state codes.
  Future<Map<String, dynamic>> weapiRaw(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, String>? cookieOverrides,
  ]) async {
    return _requestEncrypted(
      url: _weapiUrl(path, cookieOverrides),
      form: NeteaseCrypto.weapi(_withCsrf(payload, cookieOverrides)),
      cookieOverrides: cookieOverrides,
      checkBusinessCode: false,
      includeAuthCookies: true,
    );
  }

  Future<Map<String, dynamic>> plainGet(
    String path, [
    Map<String, dynamic> query = const <String, dynamic>{},
    Map<String, String>? cookieOverrides,
  ]) async {
    return _plainGet(path, query, cookieOverrides, includeAuthCookies: true);
  }

  Future<Map<String, dynamic>> publicPlainGet(
    String path, [
    Map<String, dynamic> query = const <String, dynamic>{},
  ]) async {
    return _plainGet(path, query, null, includeAuthCookies: false);
  }

  Future<Map<String, dynamic>> _plainGet(
    String path,
    Map<String, dynamic> query,
    Map<String, String>? cookieOverrides, {
    required bool includeAuthCookies,
  }) async {
    await _ensureCookies();
    try {
      final r = await dio.get(
        'https://music.163.com/api$path',
        queryParameters: query,
        options: Options(
          headers: {
            'Cookie': _cookieHeader(overrides: cookieOverrides, includeAuthCookies: includeAuthCookies),
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
      await _absorbSetCookies(r.headers);
      final obj = Map<String, dynamic>.from(
        r.data is Map ? r.data as Map : const <String, dynamic>{},
      );
      _check(obj);
      return obj;
    } on DioException catch (e) {
      throw NeteaseException('网络请求失败：${e.message}');
    }
  }

  Future<Map<String, dynamic>> plainPost(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, String>? cookieOverrides,
  ]) async {
    return _plainPost(path, payload, cookieOverrides, includeAuthCookies: true);
  }

  Future<Map<String, dynamic>> publicPlainPost(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    return _plainPost(path, payload, null, includeAuthCookies: false);
  }

  Future<Map<String, dynamic>> _plainPost(
    String path,
    Map<String, dynamic> payload,
    Map<String, String>? cookieOverrides, {
    required bool includeAuthCookies,
  }) async {
    await _ensureCookies();
    try {
      final r = await dio.post(
        'https://music.163.com/api$path',
        data: payload,
        options: Options(
          headers: {
            'Cookie': _cookieHeader(overrides: cookieOverrides, includeAuthCookies: includeAuthCookies),
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      await _absorbSetCookies(r.headers);
      final obj = Map<String, dynamic>.from(
        r.data is Map ? r.data as Map : const <String, dynamic>{},
      );
      _check(obj);
      return obj;
    } on DioException catch (e) {
      throw NeteaseException('网络请求失败：${e.message}');
    }
  }

  Future<Map<String, dynamic>> eapi(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, String>? cookieOverrides,
  ]) => _eapiRequest(
    path,
    payload,
    cookieOverrides,
    baseUrl: 'https://interface.music.163.com',
  );

  /// PC-client EAPI transport. NetEase currently routes several
  /// account-write operations (notably playlist subscribe/unsubscribe)
  /// through interfacepc.music.163.com rather than the generic EAPI host.
  Future<Map<String, dynamic>> eapiPc(
    String path, [
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, String>? cookieOverrides,
    String? antiCheatToken,
  ]) => _eapiRequest(
    path,
    payload,
    cookieOverrides,
    baseUrl: 'https://interfacepc.music.163.com',
    antiCheatToken: antiCheatToken,
  );

  /// Account operations use a coherent desktop identity, independently of
  /// the existing playback/source transports.
  Future<Map<String, dynamic>> accountEapi(
    String path, Map<String, dynamic> payload,
  ) async {
    await _ensureCookies();
    if (_cookies['deviceId']?.isNotEmpty != true) {
      final random = Random.secure();
      await setCookies({'deviceId': List.generate(16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()});
    }
    return _eapiRequest(path, payload, null,
      baseUrl: 'https://interface.music.163.com', desktopIdentity: true);
  }

  Future<String> fetchAntiCheatToken() async {
    const channel = MethodChannel('im.kumone.netease/login');
    final value = await channel.invokeMethod<String>(
      'getAntiCheatToken',
      {'cookies': Map<String, String>.from(_cookies)},
    );
    return value?.trim() ?? '';
  }

  Future<Map<String, dynamic>> subscribePlaylistInBrowser({
    required int id,
    required bool subscribe,
  }) async {
    const channel = MethodChannel('im.kumone.netease/login');
    final value = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'subscribePlaylistInWebView',
      {
        'id': id,
        'subscribe': subscribe,
        'cookies': Map<String, String>.from(_cookies),
      },
    );
    return Map<String, dynamic>.from(value ?? const <dynamic, dynamic>{});
  }

  Future<Map<String, dynamic>> _eapiRequest(
    String path,
    Map<String, dynamic> payload,
    Map<String, String>? cookieOverrides, {
    required String baseUrl,
    String? antiCheatToken,
    bool desktopIdentity = false,
  }) async {
    await _ensureCookies();
    final apiPath = '/api$path';
    final effective = _effectiveCookies(overrides: cookieOverrides);
    final header = <String, String>{
      'os': 'pc',
      'appver': '3.1.17.204416',
      'osver': 'Microsoft-Windows-10-Professional-build-19045-64bit',
      'deviceId': effective['deviceId']?.isNotEmpty == true
          ? effective['deviceId']!
          : 'kumone',
      'requestId': '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000).toString().padLeft(4, '0')}',
      'versioncode': '140',
      'buildver': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'resolution': '1920x1080',
      'channel': 'netease',
    };
    final musicU = effective['MUSIC_U'];
    final csrf = effective['__csrf'];
    if (musicU != null && musicU.isNotEmpty) header['MUSIC_U'] = musicU;
    if (csrf != null && csrf.isNotEmpty) header['__csrf'] = csrf;
    if (effective['NMTID']?.isNotEmpty == true) {
      header['NMTID'] = effective['NMTID']!;
    }
    if (antiCheatToken != null && antiCheatToken.trim().isNotEmpty) {
      header['X-antiCheatToken'] = antiCheatToken.trim();
    }

    final body = {...payload, 'header': header,
      if (desktopIdentity) 'e_r': false,
    };
    return _requestEncrypted(
      url: '$baseUrl/eapi$path',
      form: NeteaseCrypto.eapi(apiPath, body),
      cookieOverrides: desktopIdentity ? {...header, ...?cookieOverrides} : cookieOverrides,
      checkBusinessCode: true,
      antiCheatToken: antiCheatToken,
      userAgent: desktopIdentity ? 'orpheus/3.1.17.204416' : null,
    );
  }

  Map<String, dynamic> _withCsrf(
    Map<String, dynamic> payload,
    Map<String, String>? overrides,
  ) {
    final csrf = overrides?['__csrf'] ?? _cookies['__csrf'] ?? '';
    return {...payload, 'csrf_token': csrf};
  }

  Future<Map<String, dynamic>> _requestEncrypted({
    required String url,
    required Map<String, String> form,
    required bool checkBusinessCode,
    Map<String, String>? cookieOverrides,
    bool includeAuthCookies = true,
    String? antiCheatToken,
    String? userAgent,
  }) async {
    await _ensureCookies();
    try {
      final r = await dio.post(
        url,
        data: form,
        options: Options(
          headers: {
            if (userAgent != null) 'User-Agent': userAgent,
            'Cookie': _cookieHeader(
              overrides: cookieOverrides,
              includeAuthCookies: includeAuthCookies,
            ),
            if (antiCheatToken != null && antiCheatToken.trim().isNotEmpty)
              'X-antiCheatToken': antiCheatToken.trim(),
          },
        ),
      );
      await _absorbSetCookies(r.headers);
      final dynamic decodedBody = () {
        final body = r.data;
        if (body is Map) return body;
        if (body is String && body.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map) return decoded;
          } catch (_) {}
        }
        if (body is List<int>) {
          try {
            final decoded = jsonDecode(utf8.decode(body));
            if (decoded is Map) return decoded;
          } catch (_) {}
        }
        return const <String, dynamic>{};
      }();
      final obj = Map<String, dynamic>.from(decodedBody as Map);
      if (checkBusinessCode) _check(obj);
      return obj;
    } on DioException catch (e) {
      throw NeteaseException('网络请求失败：${e.message}');
    }
  }

  void _check(Map<String, dynamic> j) {
    final code = j['code'];
    if (code is num && code.toInt() != 200) {
      if (code.toInt() == 301) {
        throw const NeteaseException('需要登录', 301);
      }
      throw NeteaseException(
        (j['message'] ?? j['msg'] ?? '接口错误 (${code.toInt()})').toString(),
        code.toInt(),
      );
    }
  }
}
