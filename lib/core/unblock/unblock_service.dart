import 'dart:convert';
import '../storage/custom_source_store.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';

class ResolvedAudio {
  final Uri url;
  final String source;
  final Map<String, String> headers;

  const ResolvedAudio(
    this.url,
    this.source, {
    this.headers = const {},
  });

  bool get isLocalFile => url.scheme == 'file';
}

class CachedAudio {
  final File file;
  final String source;

  const CachedAudio({
    required this.file,
    required this.source,
  });
}

class UnblockService {
  static final Dio _dio=Dio(BaseOptions(connectTimeout:const Duration(seconds:10),receiveTimeout:const Duration(seconds:12),headers:{'User-Agent':'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36'}));
  static final Map<String, Future<File?>> _audioDownloads = {};
  static int _cacheGeneration = 0;

  static Future<Directory> _audioCacheDirectory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/kumone_audio_cache');
    await dir.create(recursive: true);
    return dir;
  }

  static String _encodedCacheKey(String quality, String source) =>
      base64Url.encode(utf8.encode('$quality|$source')).replaceAll('=', '');

  static String _decodeCacheKey(String value) {
    final padding = (4 - value.length % 4) % 4;
    return utf8.decode(
      base64Url.decode('$value${List.filled(padding, '=').join()}'),
      allowMalformed: true,
    );
  }

  static String _safeExtension(Uri uri) {
    final raw = uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last.split('.').last.toLowerCase();
    if (raw.isNotEmpty &&
        raw.length <= 8 &&
        RegExp(r'^[a-z0-9]+$').hasMatch(raw)) {
      return raw;
    }
    return 'mp3';
  }

  static Future<CachedAudio?> findCachedAudio({
    required Track track,
    required String quality,
    bool allowThirdParty = true,
  }) async {
    try {
      final dir = await _audioCacheDirectory();
      final prefix = '${track.id}_';
      CachedAudio? newest;
      DateTime newestTime = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (!name.startsWith(prefix) || name.endsWith('.part')) continue;
        final dot = name.lastIndexOf('.');
        if (dot <= prefix.length) continue;
        final token = name.substring(prefix.length, dot);
        String decoded;
        try {
          decoded = _decodeCacheKey(token);
        } catch (_) {
          continue;
        }
        final parts = decoded.split('|');
        if (parts.length != 2 || parts.first != quality) continue;
        final source = parts.last;
        if (!allowThirdParty && source != 'NetEase') continue;
        try {
          if (await entity.length() <= 0) continue;
          final modified = await entity.lastModified();
          if (newest == null || modified.isAfter(newestTime)) {
            newest = CachedAudio(file: entity, source: source);
            newestTime = modified;
          }
        } catch (_) {}
      }
      return newest;
    } catch (_) {
      return null;
    }
  }

  static Future<CachedAudio?> cacheResolvedAudio({
    required Track track,
    required String quality,
    required ResolvedAudio resolved,
  }) async {
    if (resolved.isLocalFile) {
      try {
        final file = File(resolved.url.toFilePath());
        if (await file.exists() && await file.length() > 0) {
          return CachedAudio(file: file, source: resolved.source);
        }
      } catch (_) {}
      return null;
    }

    final key = '${track.id}|$quality|${resolved.source}';
    final existing = _audioDownloads[key];
    if (existing != null) {
      final path = await existing;
      return path == null
          ? null
          : CachedAudio(file: path, source: resolved.source);
    }

    final future = _cacheResolvedAudioImpl(
      track: track,
      quality: quality,
      resolved: resolved,
    );
    _audioDownloads[key] = future;
    try {
      final path = await future;
      return path == null
          ? null
          : CachedAudio(file: path, source: resolved.source);
    } finally {
      if (identical(_audioDownloads[key], future)) {
        _audioDownloads.remove(key);
      }
    }
  }

  static Future<File?> _cacheResolvedAudioImpl({
    required Track track,
    required String quality,
    required ResolvedAudio resolved,
  }) async {
    final generation = _cacheGeneration;
    try {
      final dir = await _audioCacheDirectory();
      final token = _encodedCacheKey(quality, resolved.source);
      final extension = _safeExtension(resolved.url);
      final finalFile = File('${dir.path}/${track.id}_$token.$extension');
      if (await finalFile.exists() && await finalFile.length() > 0) {
        return finalFile;
      }

      final partialFile = File('${finalFile.path}.part');
      if (await partialFile.exists()) await partialFile.delete();
      final response = await _dio.download(
        resolved.url.toString(),
        partialFile.path,
        deleteOnError: true,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36',
            ...resolved.headers,
          },
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(seconds: 20),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (generation != _cacheGeneration) {
        try {
          if (await partialFile.exists()) await partialFile.delete();
        } catch (_) {}
        return null;
      }
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          !await partialFile.exists() ||
          await partialFile.length() <= 0) {
        return null;
      }
      if (await finalFile.exists()) await finalFile.delete();
      if (generation != _cacheGeneration) {
        try {
          if (await partialFile.exists()) await partialFile.delete();
        } catch (_) {}
        return null;
      }
      return await partialFile.rename(finalFile.path);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAudioCache({Set<String> preserveFiles = const {}}) async {
    _cacheGeneration++;
    final normalized = preserveFiles
        .map((path) => File(path).absolute.path)
        .toSet();

    Future<void> clearDir(Directory dir) async {
      try {
        if (!await dir.exists()) return;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final path = File(entity.path).absolute.path;
          if (normalized.contains(path)) continue;
          try {
            await entity.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    try {
      final root = await getApplicationSupportDirectory();
      await clearDir(Directory('${root.path}/kumone_audio_cache'));
    } catch (_) {}
    _audioDownloads.clear();
  }

  static Future<ResolvedAudio?> resolve(Track track) async {
    await for (final audio in candidates(track)) { return audio; }
    return null;
  }

  static Stream<ResolvedAudio> candidates(Track track, {Dio? client}) async* {
    final sources = await CustomSourceStore.readSources();
    for (final source in sources.where((e) => e.enabled)) {
      try {
        final endpoint = Uri.parse(source.endpoint);
        final response = await (client ?? _dio).getUri(endpoint.replace(queryParameters: {
          ...endpoint.queryParameters,
          'id': '${track.id}', 'name': track.name, 'artist': track.artistNames,
          'album': track.album.name, 'durationMs': '${track.durationMs}',
        }));
        final body = response.data is String ? jsonDecode(response.data) : response.data;
        if (body is! Map || body['url'] is! String) continue;
        final url = Uri.tryParse(body['url'] as String);
        if (url == null || url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) continue;
        final headers = <String, String>{};
        if (body['headers'] is Map) {
          for (final entry in (body['headers'] as Map).entries) {
            if (entry.key is String && entry.value is String) {
              headers[entry.key as String] = entry.value as String;
            }
          }
        }
        yield ResolvedAudio(url, 'Custom:${source.id}:${source.name}', headers: headers);
      } catch (_) { /* Try the next user-enabled endpoint. */ }
    }
  }
}
