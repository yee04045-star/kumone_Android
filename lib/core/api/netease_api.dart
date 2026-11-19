import 'dart:convert';
import 'netease_client.dart';
import '../models/models.dart';

class HighQualityPlaylistResult {
  final List<PlaylistSummary> playlists;
  final bool more;
  final int lasttime;

  const HighQualityPlaylistResult({
    required this.playlists,
    required this.more,
    required this.lasttime,
  });
}

class NeteaseApi {
  NeteaseApi._(); static final instance=NeteaseApi._(); final c=NeteaseClient.instance;

  // Mirrors the iOS ImageCache idea at the URL-resolution layer: once a
  // playlist cover has been resolved successfully, list/detail/search cards
  // can reuse the same URL without another metadata request.
  final Map<int, String> _playlistCoverCache = {};

  Future<List<ToplistItem>> toplists() async {
    try {
      final j = await c.eapi('/toplist');
      final list = (j['list'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ToplistItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}
    try {
      final j = await c.weapi('/toplist/detail');
      return (j['list'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ToplistItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AlbumSummary>> newAlbums({int limit = 30, int offset = 0}) async {
    // iOS reference: `/album/new` + area=ALL.  `/album/newest` is kept as a
    // compatibility fallback because some gateways expose only the public
    // newest-albums route.  We do not fabricate album data when every route is
    // empty; the UI simply omits the shelf in that case.
    final payload = {
      'area': 'ALL',
      'limit': limit,
      'offset': offset,
      'total': true,
    };
    Object? lastError;
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/album/new', payload),
      () => c.weapi('/album/new', {...payload, 'type': 'new'}),
      () => c.weapi('/album/new', {...payload, 'type': 'hot'}),
      () => c.weapi('/album/newest', {'limit': limit, 'offset': offset}),
      () => c.plainGet('/album/new', payload),
      () => c.plainGet('/album/newest', {'limit': limit, 'offset': offset}),
      () => c.publicWeapi('/album/new', payload),
      () => c.publicWeapi('/album/newest', {'limit': limit, 'offset': offset}),
      () => c.publicPlainGet('/album/new', payload),
      () => c.publicPlainGet('/album/newest', {'limit': limit, 'offset': offset}),
      () => c.plainPost('/album/new', payload),
      () => c.publicPlainPost('/album/new', payload),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final nested = _map(j['data']);
        final raw = j['albums'] ??
            j['album'] ??
            nested?['albums'] ??
            nested?['album'];
        final values = _mapList(raw)
            .map(AlbumSummary.fromJson)
            .where((a) => a.id > 0 && a.name.trim().isNotEmpty)
            .toList(growable: false);
        if (values.isNotEmpty) return await _hydrateAlbumCovers(values);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is NeteaseException) throw lastError;
    return const <AlbumSummary>[];
  }
  // QR flow mirrors the iOS client exactly: type=1, login?codekey=...,
  // then poll /login/qrcode/client/login with the same type.
  Future<String> qrKey() async {
    // Keep the QR bootstrap identical to the iOS client: the encrypted
    // /weapi endpoint is authoritative because it establishes the same
    // session/cookie contract used by qrCheck().
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapiRaw('/login/qrcode/unikey', {'type': 1}),
      () => c.plainGet('/login/qr/key', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    ];
    for (final request in candidates) {
      try {
        final j = await request();
        final data = j['data'];
        final key = asString(j['unikey']) ??
            asString(data is Map ? data['unikey'] : null);
        if (key != null && key.isNotEmpty) return key;
      } catch (_) {}
    }
    throw const NeteaseException('二维码获取失败');
  }

  String qrLoginUrl(String key) =>
      'https://music.163.com/login?codekey=$key';

  Future<QrStatus> qrCheck(String key) async {
    // IMPORTANT: poll the same encrypted endpoint used by iOS first.
    // The successful 803 response is where NetEase may send MUSIC_U via
    // Set-Cookie. Falling back to the old plain endpoint first can observe
    // the QR state but lose the authenticated session.
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapiRaw('/login/qrcode/client/login', {
        'key': key,
        'type': 1,
      }),
      () => c.plainGet('/login/qr/check', {
        'key': key,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    ];
    for (final request in candidates) {
      try {
        final j = await request();
        final nested = j['data'] is Map
            ? Map<String, dynamic>.from(j['data'] as Map)
            : const <String, dynamic>{};
        final cookie = asString(j['cookie']) ?? asString(nested['cookie']);
        if (cookie != null && cookie.isNotEmpty) {
          await c.ingestCookieString(cookie);
        }
        final rawProfile = j['profile'] is Map
            ? j['profile']
            : (nested['profile'] is Map ? nested['profile'] : null);
        UserProfile? profile;
        if (rawProfile is Map) {
          profile = UserProfile.fromJson(Map<String, dynamic>.from(rawProfile));
        }
        final code = asInt(j['code'] ?? nested['code'], -1);
        if (code >= 0) {
          return QrStatus(
            code,
            asString(j['message']) ?? asString(nested['message']),
            asString(j['nickname']) ?? asString(nested['nickname']) ?? profile?.nickname,
            asString(j['avatarUrl']) ?? asString(nested['avatarUrl']) ?? profile?.avatarUrl,
            profile,
          );
        }
      } catch (_) {}
    }
    throw const NeteaseException('二维码状态获取失败');
  }
  Future<void> sendSms(String phone,{String country='86'}) async {await c.weapi('/sms/captcha/sent',{'ctcode':country,'cellphone':phone,'secrete':'music_middleuser_pclogin'});}
  Future<void> loginCellphone(String phone,String captcha,{String country='86'}) async {await c.weapi('/w/login/cellphone',{'type':'1','https':'true','phone':phone,'countrycode':country,'captcha':captcha,'remember':'true','secureCaptcha':''}); if(!c.isLoggedIn)throw const NeteaseException('登录失败，请重试');}
  Future<void> ensureGuestSession() => c.ensureGuestSession();

  Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  Map<String, dynamic>? _mapJsonString(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {}
    }
    return null;
  }

  List<int> _intList(dynamic value) {
    if (value is List) {
      return value.map(asInt).where((id) => id > 0).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map(asInt).where((id) => id > 0).toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  UserProfile? _profileFromResponse(Map<String, dynamic> j) {
    final candidates = <dynamic>[
      j['profile'],
      _map(j['data'])?['profile'],
      j['user'],
      _map(j['data'])?['user'],
    ];
    for (final raw in candidates) {
      final map = _map(raw);
      if (map == null) continue;
      final value = UserProfile.fromJson(map);
      if (value.userId > 0) return value;
    }
    final account = _map(j['account']) ?? _map(j['data']);
    if (account != null) {
      final value = UserProfile.fromJson(account);
      if (value.userId > 0) return value;
    }
    return null;
  }

  Future<UserProfile?> userAccount() async {
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/w/nuser/account/get'),
      () => c.plainPost('/w/nuser/account/get'),
      () => c.plainGet('/w/nuser/account/get'),
    ];
    Object? last;
    for (final request in candidates) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final profile = _profileFromResponse(j);
        if (profile != null) return profile;
        last = const NeteaseException('账号接口返回成功，但没有有效 profile');
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    throw NeteaseException('账号资料读取失败：${last ?? '未知错误'}');
  }

  Future<UserProfile?> userDetail(int uid) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/user/detail', {'uid': uid}),
      () => c.plainGet('/user/detail', {'uid': uid}),
      () => c.publicPlainGet('/user/detail', {'uid': uid}),
    ];
    for (final request in requests) {
      try {
        final profile = _profileFromResponse(
          await request().timeout(const Duration(seconds: 8)),
        );
        if (profile != null) return profile;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> userAvatar(int uid) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/w/nuser/account/get'),
      () => c.weapi('/user/detail', {'uid': uid}),
      () => c.plainGet('/user/detail', {'uid': uid}),
      () => c.publicPlainGet('/user/detail', {'uid': uid}),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final profile = _profileFromResponse(j);
        final candidates = <Map<String, dynamic>>[
          if (profile != null) {
            'avatarUrl': profile.avatarUrl,
            'userId': profile.userId,
          },
          if (j['profile'] is Map) Map<String, dynamic>.from(j['profile'] as Map),
          if (_map(j['data'])?['profile'] is Map)
            Map<String, dynamic>.from(_map(j['data'])!['profile'] as Map),
          if (j['user'] is Map) Map<String, dynamic>.from(j['user'] as Map),
          if (_map(j['data'])?['user'] is Map)
            Map<String, dynamic>.from(_map(j['data'])!['user'] as Map),
        ];
        for (final item in candidates) {
          final url = asUrlString(item['avatarUrl']) ??
              asUrlString(item['avatarUrl120']) ??
              asUrlString(item['avatarUrlStr']) ??
              asUrlString(item['avatar']) ??
              asUrlString(item['userAvatar']) ??
              asUrlString(item['userPicUrl']);
          if (url != null) return url;
        }
      } catch (_) {}
    }
    return null;
  }
  Future<void> logout() async {try{await c.weapi('/logout');}finally{await c.clearAuth();}}
  Future<void> refreshLogin() async {try{await c.weapi('/login/token/refresh');}catch(_){}}

  Future<List<PlaylistSummary>> userPlaylists(int uid) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/user/playlist', {'uid': uid, 'limit': 2000, 'offset': 0, 'includeVideo': true}),
      () => c.plainGet('/user/playlist', {'uid': uid, 'limit': 2000, 'offset': 0, 'includeVideo': true}),
    ];
    Object? last;
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(j['data']);
        final raw = j['playlist'] ??
            data?['playlist'] ??
            data?['playlists'] ??
            j['result'];
        if (raw is List) {
          final values = raw
              .whereType<Map>()
              .map((e) => PlaylistSummary.fromJson(Map<String, dynamic>.from(e)))
              .where((p) => p.id > 0)
              .toList();
          if (values.isNotEmpty) return values;
        }
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    return const [];
  }

  Future<Set<int>> likedTrackIds(int uid) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.accountEapi('/song/like/get', {'uid': uid}),
      () => c.weapi('/song/like/get', {'uid': uid}),
      () => c.plainGet('/song/like/get', {'uid': uid}),
      () => c.weapi('/song/like', {'uid': uid}),
      () => c.plainGet('/song/like', {'uid': uid}),
      () => c.publicPlainGet('/song/like/get', {'uid': uid}),
    ];
    Object? last;
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(j['data']);
        final raw = j['ids'] ?? data?['ids'] ?? j['songIds'] ?? data?['songIds'];
        final ids = _intList(raw).toSet();
        if (ids.isNotEmpty) return ids;
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    return const <int>{};
  }

  Future<List<PlayRecordItem>> playRecords(int uid, {bool week = false}) async {
    final payload = {'uid': uid, 'type': week ? 1 : 0};
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v1/play/record', payload),
      () => c.plainGet('/v1/play/record', payload),
      () => c.weapi('/user/record', payload),
      () => c.plainGet('/user/record', payload),
    ];
    Object? last;
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final dynamic dataRaw = j['data'];
        final data = _map(dataRaw);
        final raw = week
            ? (j['weekData'] ?? data?['weekData'])
            : (j['allData'] ?? data?['allData']);
        final direct = raw is List
            ? raw
            : (raw is String && raw.trim().isNotEmpty
                ? (() {
                    try {
                      final decoded = jsonDecode(raw);
                      return decoded is List ? decoded : const [];
                    } catch (_) {
                      return const [];
                    }
                  })()
                : (dataRaw is List
                    ? dataRaw
                    : (data?['list'] is List ? data!['list'] as List : const [])));
        final values = direct
            .whereType<Map>()
            .map((e) => PlayRecordItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.song.id > 0 && e.song.name.isNotEmpty)
            .toList();
        if (values.isNotEmpty) return values;
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    return const [];
  }

  Future<CloudSongsResult> cloudSongs({int limit = 1000, int offset = 0}) async {
    final payload = {'limit': limit, 'offset': offset};
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v1/cloud/get', payload),
      () => c.plainGet('/v1/cloud/get', payload),
      () => c.weapi('/cloud/get', payload),
      () => c.plainGet('/user/cloud', payload),
    ];
    Object? last;
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final raw = j['data'] ?? j['result'];
        final items = (raw is List ? raw : const [])
            .whereType<Map>()
            .map((e) => CloudSongItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (raw is List) {
          return CloudSongsResult(
            items: items,
            hasMore: asBool(j['hasMore']),
            size: asInt(j['size']) == 0 ? null : asInt(j['size']),
            maxSize: asInt(j['maxSize']) == 0 ? null : asInt(j['maxSize']),
          );
        }
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    return const CloudSongsResult(items: []);
  }
  Future<void> deleteCloudSong(int id) async {
    await c.weapi('/cloud/del', {'songIds': '[$id]'});
  }

  Future<void> likeTrack(int id, bool like) async {
    await c.accountEapi('/radio/like', {
      'alg': 'itembased',
      'trackId': '$id',
      'like': like ? 'true' : 'false',
      'time': '3',
    });
  }

  Future<void> addToMusicBlacklist(int id, {bool artist = false}) async {
    if (!c.isLoggedIn) throw const NeteaseException('请先登录');
    await c.accountEapi('/music-blacklist/add', {
      'contentType': artist ? 'artist' : 'song',
      'contentIdList': ['$id'],
    });
  }

  Future<CloudSongsResult> allCloudSongs() async {
    final items = <CloudSongItem>[];
    final seen = <int>{};
    CloudSongsResult page = const CloudSongsResult(items: []);
    var offset = 0;
    do {
      page = await cloudSongs(limit: 200, offset: offset);
      if (page.items.isEmpty) break;
      final fresh = page.items.where((e) => seen.add(e.songId)).toList();
      if (fresh.isEmpty) break; // Protect against an endpoint ignoring offset.
      items.addAll(fresh);
      offset += page.items.length;
    } while (page.hasMore);
    return CloudSongsResult(items: items, size: page.size, maxSize: page.maxSize);
  }

  Future<List<AlbumSummary>> likedAlbums() async {
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/album/sublist', {'limit': 500, 'offset': 0, 'total': true}),
      () => c.plainGet('/album/sublist', {'limit': 500, 'offset': 0, 'total': true}),
    ];
    for (final request in candidates) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final raw = j['data'];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => AlbumSummary.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id > 0)
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<List<ArtistSummary>> likedArtists() async {
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/artist/sublist', {'limit': 500, 'offset': 0, 'total': true}),
      () => c.plainGet('/artist/sublist', {'limit': 500, 'offset': 0, 'total': true}),
    ];
    for (final request in candidates) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final raw = j['data'];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => ArtistSummary.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id > 0)
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<void> subscribeAlbum(int id, bool subscribe) async {
    await c.weapi('/album/${subscribe ? 'sub' : 'unsub'}', {'id': id});
  }

  Future<void> subscribeArtist(int id, bool subscribe) async {
    if (id <= 0) {
      throw const NeteaseException('歌手 ID 无效');
    }

    // The original client uses an unencrypted browser form for this write.
    // EAPI is rejected by risk control; WEAPI is not the same transport.
    await c.plainPost('/artist/${subscribe ? 'sub' : 'unsub'}', {
      'artistId': '$id',
      'artistIds': '[$id]',
    });
  }

  Future<void> scrobbleStart({required int trackId}) async {
    await _sendWeblog({
      'action': 'startplay',
      'json': {
        'id': trackId,
        'type': 'song',
        'mainsite': '1',
        'mainsiteWeb': '1',
        'content': 'id=0',
      },
    });
  }

  Future<void> scrobbleFinish({required int trackId, required int seconds, bool completed = false}) async {
    await _sendWeblog({
      'action': 'play',
      'json': {
        'download': 0,
        'end': completed ? 'playend' : 'playend',
        'id': trackId,
        'sourceId': '0',
        'time': seconds,
        'type': 'song',
        'wifi': 0,
        'source': 'list',
        'mainsite': '1',
        'mainsiteWeb': '1',
        'content': 'id=0',
      },
    });
  }

  Future<void> _sendWeblog(Map<String, dynamic> log) async {
    // iOS reference uses the desktop/osx client cookie for /feedback/weblog.
    // Using the generic pc cookie can return success while not writing the
    // event into the user's 最近播放 feed.
    try {
      await c.eapi('/feedback/weblog', {
        'logs': jsonEncode([log]),
      }, {'os': 'osx'});
    } catch (_) {}
  }

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  List<PlaylistSummary> _playlistsFromResponse(Map<String, dynamic> j) {
    final nested = _map(j['data']);
    final raw = j['result'] ??
        j['recommend'] ??
        j['playlists'] ??
        j['playlist'] ??
        nested?['result'] ??
        nested?['recommend'] ??
        nested?['playlists'] ??
        nested?['playlist'];
    return _mapList(raw)
        .map(PlaylistSummary.fromJson)
        .where((p) => p.id > 0)
        .toList(growable: false);
  }

  Future<List<PlaylistSummary>> personalizedPlaylists({int limit=30}) async {
    // iOS reference: `/personalized/playlist` over weapi.  Keep that as the
    // authoritative path, then accept the same payload over compatibility
    // transports used elsewhere in the Android client.  Importantly, continue
    // trying candidates when a transport succeeds with an empty payload so the
    // home shelf does not disappear merely because one route changed shape.
    final payload = {'limit': limit, 'total': true, 'n': 1000};
    Object? lastError;
    for (final request in <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/personalized/playlist', payload),
      () => c.publicWeapi('/personalized/playlist', payload),
      () => c.plainGet('/personalized/playlist', payload),
      () => c.publicPlainGet('/personalized/playlist', payload),
      () => c.plainPost('/personalized/playlist', payload),
      () => c.publicPlainPost('/personalized/playlist', payload),
    ]) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final result = _playlistsFromResponse(j);
        if (result.isNotEmpty) return await hydratePlaylistCovers(result);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is NeteaseException) throw lastError;
    return const <PlaylistSummary>[];
  }

  Future<List<PlaylistSummary>> recommendResource() async {
    // iOS reference uses `/v1/discovery/recommend/resource` when logged in.
    // Keep the exact route first and tolerate GET/POST/public compatibility
    // paths because Android network stacks can receive different server-side
    // routing depending on cookies / gateway behavior.
    Object? lastError;
    for (final request in <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v1/discovery/recommend/resource'),
      () => c.plainGet('/v1/discovery/recommend/resource'),
      () => c.plainPost('/v1/discovery/recommend/resource'),
      () => c.publicWeapi('/v1/discovery/recommend/resource'),
      () => c.publicPlainGet('/v1/discovery/recommend/resource'),
      () => c.publicPlainPost('/v1/discovery/recommend/resource'),
    ]) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final result = _playlistsFromResponse(j);
        if (result.isNotEmpty) return await hydratePlaylistCovers(result);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is NeteaseException) throw lastError;
    return const <PlaylistSummary>[];
  }

  Future<List<Track>> dailyRecommendSongs() async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v3/discovery/recommend/songs'),
      () => c.weapi('/recommend/songs'),
      () => c.plainGet('/v3/discovery/recommend/songs'),
      () => c.plainGet('/recommend/songs'),
      () => c.plainPost('/v3/discovery/recommend/songs', {'afresh': false}),
    ];
    Object? last;
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = j['data'];
        final nested = data is Map ? Map<String, dynamic>.from(data) : null;
        final primary = decodeTracks(nested?['dailySongs'] ?? nested?['songs']);
        if (primary.isNotEmpty) return await enrichTracksMetadata(primary);
        final alternate = decodeTracks(j['dailySongs'] ?? j['recommend'] ?? j['songs']);
        if (alternate.isNotEmpty) return await enrichTracksMetadata(alternate);
        if (data is Map && (data.containsKey('dailySongs') || data.containsKey('songs'))) return const [];
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    throw const NeteaseException('每日推荐读取失败');
  }
  List<Track> _decodeIntelligenceTracks(dynamic value) {
    dynamic raw = value;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const <Track>[];
      }
    }

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      raw = map['data'] ?? map['songs'] ?? map['result'] ?? map['recommend'];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          raw = jsonDecode(raw);
        } catch (_) {
          return const <Track>[];
        }
      }
    }

    if (raw is! List) return const <Track>[];

    final tracks = <Track>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      dynamic candidate = item['songInfo'] ?? item['song'] ?? item['track'];
      if (candidate is String && candidate.trim().isNotEmpty) {
        try {
          candidate = jsonDecode(candidate);
        } catch (_) {
          candidate = null;
        }
      }
      final source = candidate is Map
          ? Map<String, dynamic>.from(candidate)
          : item;
      try {
        final track = Track.fromJson(source);
        if (track.id > 0) tracks.add(track);
      } catch (_) {
        // One malformed recommendation must not discard all usable songs.
      }
    }
    return tracks;
  }

  Future<List<Track>> intelligenceList(int songId, int playlistId) async {
    // Primary path is byte-for-byte equivalent in meaning to iOS:
    // POST /weapi/playmode/intelligence/list with one random liked-song seed
    // and count=1. A couple of transport fallbacks are kept *after* that exact
    // request because Android/Dio can encounter deployments that expose this
    // endpoint through eapi or the plain /api route. They never alter the iOS
    // payload or queue semantics; they only rescue an empty/unusable response.
    final payload = <String, dynamic>{
      'songId': songId,
      'type': 'fromPlayOne',
      'playlistId': playlistId,
      'startMusicId': songId,
      'count': 1,
    };

    Object? lastError;
    final requests = <Future<Map<String, dynamic>> Function()>[
      // 1. Exact iOS transport.
      () => c.weapi('/playmode/intelligence/list', payload),
      // 2. Some current client stacks expose the same endpoint through eapi.
      () => c.eapi('/playmode/intelligence/list', payload),
      // 3. Direct /api fallback used by lightweight NetEase gateways.
      () => c.plainPost('/playmode/intelligence/list', payload),
    ];

    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 10));
        final tracks = _decodeIntelligenceTracks(j['data'] ?? j);
        if (tracks.isNotEmpty) {
          return await enrichTracksMetadata(tracks);
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError is NeteaseException) throw lastError;
    return const <Track>[];
  }

  Future<List<Track>> personalizedNewsongs({int limit=10}) async {final j=await c.weapi('/personalized/newsong',{'type':'recommend','limit':limit,'areaId':0});return (j['result'] as List? ?? const[]).whereType<Map>().map((e)=>e['song'] is Map?Track.fromJson(Map<String,dynamic>.from(e['song'])):null).whereType<Track>().toList();}
  Future<List<Track>> similarSongs(int id,{int limit=30}) async {final j=await c.weapi('/v1/discovery/simiSong',{'songid':id,'limit':limit,'offset':0});return decodeTracks(j['songs']);}
  Future<Track> dislikeRecommendedSong(int id) async {
    final j = await c.weapi('/v2/discovery/recommend/dislike', {'id': id});
    final raw = j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : null;
    final track = raw == null ? null : Track.fromJson(raw);
    if (track == null || track.id <= 0) throw const NeteaseException('减少推荐失败');
    return track;
  }
  Future<List<Track>> personalFm() async {
    Map<String, dynamic> j;
    try {
      j = await c.plainPost('/v1/radio/get');
    } catch (_) {
      j = await c.weapi('/v1/radio/get');
    }
    return enrichTracksMetadata(decodeTracks(j['data']));
  }
  Future<void> fmTrash(int id) async {await c.weapi('/radio/trash/add?alg=RT&songId=$id&time=25',{'songId':id});}

  Future<String?> playlistCover(int id) async {
    if (id <= 0) return null;
    final cached = _playlistCoverCache[id];
    if (cached != null && cached.isNotEmpty) return cached;
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v6/playlist/detail', {'id': id, 'n': 1, 's': 8}),
      () => c.weapi('/playlist/detail', {'id': id, 'n': 1, 's': 8}),
      () => c.weapi('/v3/playlist/detail', {'id': id, 'n': 1, 's': 8}),
      () => c.publicWeapi('/v6/playlist/detail', {'id': id, 'n': 1, 's': 8}),
      () => c.plainGet('/v6/playlist/detail', {'id': id, 'n': 1, 's': 8}),
      () => c.publicPlainGet('/playlist/detail', {'id': id, 'n': 1, 's': 8}),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(j['data']);
        final raw = j['playlist'] ??
            data?['playlist'] ??
            (data != null && data.containsKey('id') ? data : null);
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final cover = asUrlString(m['coverImgUrl']) ??
            asUrlString(m['coverImgUrlStr']) ??
            asUrlString(m['picUrl']) ??
            asUrlString(m['picUrlStr']) ??
            asUrlString(m['cover']) ??
            asUrlString(m['coverUrl']) ??
            asUrlString(m['imgUrl']) ??
            asUrlString(m['imageUrl']);
        if (cover != null && cover.isNotEmpty) {
          _playlistCoverCache[id] = cover;
          return cover;
        }

        final inlineTracks = decodeTracks(m['tracks']);
        final inlineCover = inlineTracks.firstOrNull?.album.picUrl;
        if (inlineCover != null && inlineCover.isNotEmpty) {
          _playlistCoverCache[id] = inlineCover;
          return inlineCover;
        }

        final ids = (m['trackIds'] as List? ?? const [])
            .map((e) => e is Map ? asInt(e['id']) : asInt(e))
            .where((e) => e > 0)
            .take(5)
            .toList();
        if (ids.isNotEmpty) {
          final detailed = await songDetails(ids);
          final detailedCover = detailed.firstOrNull?.album.picUrl;
          if (detailedCover != null && detailedCover.isNotEmpty) {
            _playlistCoverCache[id] = detailedCover;
            return detailedCover;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<PlaylistSummary?> playlistBrief(int id) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v6/playlist/detail', {'id': id, 'n': 1, 's': 0}),
      () => c.weapi('/playlist/detail', {'id': id, 'n': 1, 's': 0}),
      () => c.plainGet('/v6/playlist/detail', {'id': id, 'n': 1, 's': 0}),
      () => c.publicPlainGet('/playlist/detail', {'id': id, 'n': 1, 's': 0}),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(j['data']);
        final raw = j['playlist'] ?? data?['playlist'] ?? (data != null && data.containsKey('id') ? data : null);
        if (raw is Map) {
          final summary = PlaylistSummary.fromJson(
            Map<String, dynamic>.from(raw),
          );
          final cover = summary.coverUrl?.trim();
          if (summary.id > 0 && cover != null && cover.isNotEmpty) {
            _playlistCoverCache[summary.id] = cover;
          }
          return summary;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<PlaylistDetailResult> playlistDetail(int id) async {
    // Public playlists are readable as a guest. Use the same /weapi route as
    // iOS first, then anonymous/legacy transports only as compatibility fallbacks.
    await c.ensureGuestSession();
    Map<String, dynamic>? j;
    Object? lastError;
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v6/playlist/detail', {'id': id, 'n': 100000, 's': 8}),
      () => c.publicWeapi('/v6/playlist/detail', {'id': id, 'n': 100000, 's': 8}),
      () => c.publicPlainGet('/v6/playlist/detail', {'id': id, 'n': 100000, 's': 8}),
      () => c.publicPlainGet('/playlist/detail', {'id': id, 'n': 100000, 's': 8}),
      () => c.plainGet('/v6/playlist/detail', {'id': id, 'n': 100000, 's': 8}),
      () => c.weapi('/v3/playlist/detail', {'id': id, 'n': 1000, 's': 8}),
    ];
    for (final request in candidates) {
      try {
        final value = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(value['data']);
        if (value['playlist'] is Map || data?['playlist'] is Map || (data != null && data.containsKey('id'))) {
          j = value;
          if (j['playlist'] is! Map && data != null) {
            j['playlist'] = data['playlist'] is Map ? data['playlist'] : data;
          }
          break;
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (j == null) {
      throw NeteaseException('歌单数据读取失败：${lastError ?? '未知错误'}');
    }

    final raw = j['playlist'];
    if (raw is! Map) throw const NeteaseException('歌单数据为空');
    final p = PlaylistDetail.fromJson(Map<String, dynamic>.from(raw));
    final priv = (j['privileges'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TrackPrivilege.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    var tracks = p.tracks;
    if (p.trackIds.isNotEmpty) {
      final knownIds = tracks.map((t) => t.id).toSet();
      final missing = p.trackIds.where((trackId) => !knownIds.contains(trackId)).toList();
      if (missing.isNotEmpty) {
        try {
          final extra = await songDetails(missing.take(1000).toList());
          if (extra.isNotEmpty) {
            final byId = <int, Track>{for (final t in tracks) t.id: t};
            for (final t in extra) {
              byId[t.id] = t;
            }
            tracks = p.trackIds.map((trackId) => byId[trackId]).whereType<Track>().toList();
          }
        } catch (_) {}
      }
      if (tracks.isEmpty || (p.trackCount > 0 && tracks.length < p.trackCount)) {
        try {
          Map<String, dynamic>? all;
          final allRequests = <Future<Map<String, dynamic>> Function()>[
            () => c.publicPlainGet('/playlist/track/all', {
              'id': id,
              'limit': p.trackCount > 0
                  ? p.trackCount.clamp(1, 1000).toInt()
                  : 500,
              'offset': 0,
            }),
            () => c.plainGet('/playlist/track/all', {
              'id': id,
              'limit': p.trackCount > 0
                  ? p.trackCount.clamp(1, 1000).toInt()
                  : 500,
              'offset': 0,
            }),
          ];
          for (final request in allRequests) {
            try {
              final candidate =
                  await request().timeout(const Duration(seconds: 8));
              final songs = decodeTracks(
                candidate['songs'] ?? _mapJsonString(candidate['data'])?['songs'],
              );
              if (songs.isNotEmpty) {
                all = candidate;
                break;
              }
            } catch (_) {}
          }
          if (all != null) {
            final direct = decodeTracks(
              all['songs'] ?? _mapJsonString(all['data'])?['songs'],
            );
            if (direct.isNotEmpty) {
              final byId = <int, Track>{for (final t in direct) t.id: t};
              final ordered = p.trackIds
                  .map((trackId) => byId[trackId])
                  .whereType<Track>()
                  .toList();
              tracks = ordered.isNotEmpty ? ordered : direct;
            }
          }
        } catch (_) {}
      }
    }

    final normalized = PlaylistDetail(
      id: p.id,
      name: p.name,
      cover: p.cover ?? tracks.firstOrNull?.album.picUrl,
      creator: p.creator,
      description: p.description, trackCount: p.trackCount, playCount: p.playCount,
      subscribedCount: p.subscribedCount, subscribed: p.subscribed,
      trackIds: p.trackIds, tracks: tracks,
    );
    final normalizedCover = normalized.cover?.trim();
    if (normalizedCover != null && normalizedCover.isNotEmpty) {
      _playlistCoverCache[id] = normalizedCover;
    }
    return PlaylistDetailResult(normalized, priv);
  }

  /// Song details are publicly readable for public playlists. Keep the public
  /// transport first so anonymous users never hit the 301 auth gate after a
  /// playlist detail response only contains trackIds. Authenticated weapi is a
  /// fallback for private libraries.
  Future<List<Track>> playlistTracksAll(int id, {int limit = 1000}) async {
    final payload = {'id': id, 'limit': limit.clamp(1, 1000), 'offset': 0};
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/playlist/track/all', payload),
      () => c.publicWeapi('/playlist/track/all', payload),
      () => c.plainGet('/playlist/track/all', payload),
      () => c.publicPlainGet('/playlist/track/all', payload),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 12));
        final nested = _mapJsonString(j['data']);
        final tracks = decodeTracks(j['songs'] ?? nested?['songs']);
        if (tracks.isNotEmpty) return await enrichTracksMetadata(tracks);
      } catch (_) {}
    }
    return const [];
  }

  Future<List<Track>> songDetails(List<int> ids) async {
    if (ids.isEmpty) return [];
    final results = <Track>[];
    for (var i = 0; i < ids.length; i += 200) {
      final batchEnd = (i + 200).clamp(0, ids.length).toInt();
      final batch = ids.sublist(i, batchEnd);
      final cstr = '[${batch.map((id) => '{"id":$id}').join(',')}]';
      final requests = <Future<Map<String, dynamic>> Function()>[
        () => c.weapi('/v3/song/detail', {'c': cstr}),
        () => c.publicWeapi('/v3/song/detail', {'c': cstr}),
        () => c.publicPlainPost('/v3/song/detail', {'c': cstr}),
        () => c.publicPlainGet('/song/detail', {'ids': batch.join(',')}),
        () => c.plainPost('/v3/song/detail', {'c': cstr}),
      ];
      for (final request in requests) {
        try {
          final j = await request();
          final decoded = decodeTracks(j['songs']);
          if (decoded.isNotEmpty) {
            results.addAll(decoded);
            break;
          }
        } catch (_) {}
      }
    }
    return results;
  }

  Future<List<Track>> enrichTracksMetadata(List<Track> source) async {
    if (source.isEmpty) return source;
    final needs = source
        .where((t) => t.album.picUrl == null || t.album.picUrl!.isEmpty || t.album.name.isEmpty)
        .map((t) => t.id)
        .toSet()
        .toList();
    if (needs.isEmpty) return source;
    try {
      final detailed = await songDetails(needs);
      final map = {for (final t in detailed) t.id: t};
      return source.map((t) => map[t.id] ?? t).toList();
    } catch (_) {
      return source;
    }
  }
  Future<List<PlaylistSummary>> topPlaylists({
    String category = '全部',
    int limit = 50,
    int offset = 0,
  }) async {
    // Match the iOS reference first.  Some NetEase deployments accept the
    // historical `total="true"` string while others accept a JSON boolean,
    // so keep both forms as separate candidates.  Legacy/public transports
    // remain fallbacks only; they must never replace valid playlist data with
    // an unrelated category or chart.
    final boolTotalPayload = <String, dynamic>{
      'cat': category,
      'order': 'hot',
      'limit': limit,
      'offset': offset,
      'total': true,
    };
    final stringTotalPayload = <String, dynamic>{
      'cat': category,
      'order': 'hot',
      'limit': limit,
      'offset': offset,
      'total': 'true',
    };
    final minimalPayload = <String, dynamic>{
      'cat': category,
      'order': 'hot',
      'limit': limit,
      'offset': offset,
    };

    Object? lastError;
    final requests = <Future<Map<String, dynamic>> Function()>[
      // 1) Exact iOS request shape.
      () => c.weapi('/playlist/list', boolTotalPayload),
      // 2) Historical clients serialize total as the string "true".
      () => c.weapi('/playlist/list', stringTotalPayload),
      // 3) Same endpoint without the optional total field.
      () => c.weapi('/playlist/list', minimalPayload),
      // 4) Public encrypted transport with the same three payload shapes.
      () => c.publicWeapi('/playlist/list', boolTotalPayload),
      () => c.publicWeapi('/playlist/list', stringTotalPayload),
      () => c.publicWeapi('/playlist/list', minimalPayload),
      // 5) A plain API endpoint exists on some NetEase deployments.
      () => c.plainPost('/playlist/list', boolTotalPayload),
      () => c.plainPost('/playlist/list', stringTotalPayload),
      () => c.publicPlainPost('/playlist/list', boolTotalPayload),
      () => c.publicPlainPost('/playlist/list', stringTotalPayload),
      () => c.publicPlainGet('/playlist/list', minimalPayload),
      () => c.plainGet('/playlist/list', minimalPayload),
      // 6) Legacy public category-playlist route.
      () => c.weapi('/top/playlist', stringTotalPayload),
      () => c.weapi('/top/playlist', minimalPayload),
      () => c.publicWeapi('/top/playlist', stringTotalPayload),
      () => c.publicWeapi('/top/playlist', minimalPayload),
      () => c.publicPlainGet('/top/playlist', minimalPayload),
      () => c.plainGet('/top/playlist', minimalPayload),
      () => c.publicPlainPost('/top/playlist', minimalPayload),
      () => c.plainPost('/top/playlist', minimalPayload),
      // Cache-busting GETs for proxies that incorrectly cache an empty page.
      () => c.publicPlainGet('/top/playlist', {
        ...minimalPayload,
        '_': DateTime.now().millisecondsSinceEpoch,
      }),
      () => c.plainGet('/top/playlist', {
        ...minimalPayload,
        '_': DateTime.now().millisecondsSinceEpoch,
      }),
    ];

    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 10));
        final data = _mapJsonString(j['data']);
        final body = _mapJsonString(j['body']);
        final raw = j['playlists'] ??
            j['playlist'] ??
            j['result'] ??
            data?['playlists'] ??
            data?['playlist'] ??
            data?['result'] ??
            body?['playlists'] ??
            body?['playlist'] ??
            body?['result'];
        final result = _mapList(raw)
            .map(PlaylistSummary.fromJson)
            .where((p) => p.id > 0)
            .toList(growable: false);
        if (result.isNotEmpty) {
          // Match the iOS architecture: playlist data loading succeeds
          // independently of artwork loading.  The card resolves a missing
          // cover lazily through Artwork/playlistCover(), so a slow or broken
          // image request can never turn a valid category response into an
          // "接口未找到" error or block the whole grid.
          return result;
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError is NeteaseException) {
      throw lastError;
    }
    return const <PlaylistSummary>[];
  }

  Future<List<PlaylistSummary>> hydratePlaylistCovers(List<PlaylistSummary> source) async {
    if (source.isEmpty) return source;
    final result = List<PlaylistSummary>.from(source);
    final indices = <int>[];
    for (var i = 0; i < result.length; i++) {
      final cover = result[i].coverUrl?.trim();
      if (cover == null || cover.isEmpty) indices.add(i);
    }
    // Keep metadata hydration bounded. iOS loads artwork independently;
    // Android only uses this method where an endpoint has omitted a cover.
    final targets = indices.take(18).toList();
    await Future.wait(targets.map((index) async {
      try {
        final item = result[index];
        final cover = await playlistCover(item.id);
        if (cover != null && cover.isNotEmpty) {
          result[index] = item.copyWith(coverUrl: cover);
        }
      } catch (_) {
        // Cover failure is isolated to this card. Never fail the playlist page.
      }
    }));
    return result;
  }

  /// Force-resolve the visible batch even when the search payload contains a
  /// syntactically valid but stale/unreachable cover URL. This mirrors the iOS
  /// design (the model owns the canonical cover URL) while giving Android a
  /// metadata refresh path before the card reaches the image widget.
  Future<List<PlaylistSummary>> refreshPlaylistCovers(List<PlaylistSummary> source) async {
    if (source.isEmpty) return source;
    final result = List<PlaylistSummary>.from(source);
    await Future.wait(List.generate(result.length, (index) async {
      final item = result[index];
      final cover = await playlistCover(item.id);
      if (cover != null && cover.isNotEmpty) {
        result[index] = item.copyWith(coverUrl: cover);
      }
    }));
    return result;
  }
  Future<HighQualityPlaylistResult> highQualityPlaylistPage({
    int limit = 50,
    int before = 0,
  }) async {
    final exactPayload = {
      'cat': '全部',
      'limit': limit,
      'lasttime': before,
      'total': true,
    };
    final legacyPayload = {
      'cat': '全部',
      'limit': limit,
      'before': before,
    };
    Object? lastError;
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/playlist/highquality/list', exactPayload),
      () => c.weapi('/playlist/highquality/list', {
        'cat': '全部',
        'limit': limit,
        'lasttime': before,
        'total': 'true',
      }),
      () => c.publicWeapi('/playlist/highquality/list', exactPayload),
      () => c.publicWeapi('/playlist/highquality/list', {
        'cat': '全部',
        'limit': limit,
        'lasttime': before,
        'total': 'true',
      }),
      () => c.publicPlainPost('/playlist/highquality/list', exactPayload),
      () => c.plainPost('/playlist/highquality/list', exactPayload),
      () => c.publicPlainGet('/top/playlist/highquality', legacyPayload),
      () => c.plainGet('/top/playlist/highquality', legacyPayload),
      () => c.publicPlainPost('/top/playlist/highquality', legacyPayload),
      () => c.plainPost('/top/playlist/highquality', legacyPayload),
    ];

    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 10));
        final data = _mapJsonString(j['data']);
        final body = _mapJsonString(j['body']);
        final raw = j['playlists'] ??
            j['playlist'] ??
            j['result'] ??
            data?['playlists'] ??
            data?['playlist'] ??
            data?['result'] ??
            body?['playlists'] ??
            body?['playlist'] ??
            body?['result'];
        final result = _mapList(raw)
            .map(PlaylistSummary.fromJson)
            .where((p) => p.id > 0)
            .toList(growable: false);
        if (result.isNotEmpty) {
          return HighQualityPlaylistResult(
            playlists: result,
            more: asBool(j['more'] ?? data?['more'] ?? body?['more']),
            lasttime: asInt(j['lasttime'] ?? data?['lasttime'] ?? body?['lasttime']),
          );
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is NeteaseException) throw lastError;
    return const HighQualityPlaylistResult(
      playlists: [],
      more: false,
      lasttime: 0,
    );
  }

  Future<List<AlbumSummary>> _hydrateAlbumCovers(List<AlbumSummary> source) async {
    if (source.isEmpty) return source;
    final result = List<AlbumSummary>.from(source);
    await Future.wait(
      List.generate(result.length, (index) async {
        final item = result[index];
        final existing = item.picUrl?.trim();
        if (existing != null && existing.isNotEmpty) return;
        try {
          final detail = await album(item.id);
          final cover = detail.album.picUrl?.trim();
          if (cover != null && cover.isNotEmpty) {
            result[index] = AlbumSummary(
              id: item.id,
              name: item.name,
              picUrl: cover,
              artistName: item.artistName.isNotEmpty
                  ? item.artistName
                  : detail.album.artistName,
              publishTime: item.publishTime > 0
                  ? item.publishTime
                  : detail.album.publishTime,
              size: item.size > 0 ? item.size : detail.album.size,
              subType: item.subType ?? detail.album.subType,
              alias: item.alias,
            );
          }
        } catch (_) {
          // A single album cover failure must not discard the whole shelf.
        }
      }),
    );
    return result;
  }

  Future<List<ArtistSummary>> topArtists({int limit = 100}) async {
    Object? lastError;
    final payload = {'type': 1, 'limit': limit, 'offset': 0, 'total': true};
    for (final request in <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/toplist/artist', payload),
      () => c.plainGet('/toplist/artist', payload),
      () => c.publicWeapi('/toplist/artist', payload),
      () => c.publicPlainGet('/toplist/artist', payload),
    ]) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final nested = _map(j['data']);
        final list = _map(j['list']) ?? _map(nested?['list']);
        final raw = j['artists'] ??
            nested?['artists'] ??
            list?['artists'];
        final values = _mapList(raw)
            .map(ArtistSummary.fromJson)
            .where((a) => a.id > 0 && a.name.trim().isNotEmpty)
            .toList(growable: false);
        if (values.isNotEmpty) return await _hydrateArtistCovers(values);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is NeteaseException) throw lastError;
    return const <ArtistSummary>[];
  }

  Future<List<ArtistSummary>> _hydrateArtistCovers(List<ArtistSummary> source) async {
    if (source.isEmpty) return source;
    final result = List<ArtistSummary>.from(source);
    await Future.wait(
      List.generate(result.length, (index) async {
        final item = result[index];
        if (item.picUrl != null && item.picUrl!.trim().isNotEmpty) return;
        try {
          final detail = await artist(item.id);
          final cover = detail.artist.picUrl;
          if (cover != null && cover.trim().isNotEmpty) {
            result[index] = ArtistSummary(
            id: item.id,
            name: item.name,
            picUrl: cover,
            albumSize: item.albumSize,
            musicSize: item.musicSize,
            briefDesc: item.briefDesc,
            alias: item.alias,
            followed: item.followed,
            );
          }
        } catch (_) {}
      }),
    );
    return result;
  }

  Future<bool?> albumSubscribed(int id) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.eapi('/album/detail/dynamic', {'id': id}),
      () => c.weapi('/album/detail/dynamic', {'id': id}),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final raw = j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : j;
        if (raw.containsKey('isSub')) return asBool(raw['isSub']);
      } catch (_) {}
    }
    return null;
  }

  Future<AlbumDetailResult> album(int id) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v1/album/$id'),
      () => c.plainGet('/v1/album/$id'),
      () => c.weapi('/album', {'id': id}),
      () => c.publicWeapi('/album', {'id': id}),
      () => c.publicPlainGet('/album', {'id': id}),
      () => c.publicPlainGet('/album/detail', {'id': id}),
      () => c.plainGet('/album/detail', {'id': id}),
      () => c.publicPlainGet('/album', {'id': id, '_': DateTime.now().millisecondsSinceEpoch}),
      () => c.plainGet('/album', {'id': id, '_': DateTime.now().millisecondsSinceEpoch}),
    ];
    AlbumDetailResult? fallback;
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(j['data']);
        final rawAlbum = j['album'] ?? data?['album'] ?? (data != null && data.containsKey('id') ? data : null);
        final album = rawAlbum is Map
            ? AlbumSummary.fromJson(Map<String, dynamic>.from(rawAlbum))
            : const AlbumSummary(id: 0, name: '');
        final rawSongs = j['songs'] ?? data?['songs'] ?? (rawAlbum is Map ? rawAlbum['songs'] : null);
        var songs = decodeTracks(rawSongs);
        if (album.id > 0) {
          final enriched = songs.isNotEmpty ? await _enrichAlbumSongs(songs) : songs;
          fallback = AlbumDetailResult(album, enriched);
          if (enriched.isNotEmpty) return AlbumDetailResult(album, enriched);
        }
      } catch (_) {}
    }
    return fallback ?? const AlbumDetailResult(AlbumSummary(id: 0, name: ''), []);
  }

  Future<String?> albumCover(int id) async {
    if (id <= 0) return null;
    try {
      final detail = await album(id);
      final cover = detail.album.picUrl;
      if (cover != null && cover.trim().isNotEmpty) return cover;
      return detail.songs.firstOrNull?.album.picUrl;
    } catch (_) {
      return null;
    }
  }

  Future<List<Track>> _enrichAlbumSongs(List<Track> songs) async {
    final needs = songs.where((t) => t.album.id <= 0 || t.album.picUrl == null || t.album.picUrl!.isEmpty).map((t) => t.id).toList();
    if (needs.isEmpty) return songs;
    try {
      final detailed = await songDetails(needs);
      final map = {for (final t in detailed) t.id: t};
      return songs.map((t) => map[t.id] ?? t).toList();
    } catch (_) {
      return songs;
    }
  }

  Future<ArtistDetailResult> artist(int id) async {
    Object? last;
    for (final request in <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/v1/artist/$id'),
      () => c.weapi('/artist/detail', {'id': id}),
      () => c.plainGet('/v1/artist/$id'),
      () => c.publicPlainGet('/artist/detail', {'id': id}),
    ]) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final raw = j['artist'] ?? (j['data'] is Map ? j['data']['artist'] : null);
        if (raw is Map) {
          final artist = ArtistSummary.fromJson(Map<String, dynamic>.from(raw));
          if (artist.id > 0) {
            return ArtistDetailResult(artist, decodeTracks(j['hotSongs'] ?? j['songs']));
          }
        }
      } catch (e) {
        last = e;
      }
    }
    if (last is NeteaseException) throw last;
    throw const NeteaseException('歌手资料读取失败');
  }
  Future<String?> artistCover(int id) async {
    if (id <= 0) return null;
    try {
      final detail = await artist(id);
      final cover = detail.artist.picUrl;
      return cover != null && cover.trim().isNotEmpty ? cover : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<AlbumSummary>> artistAlbums(int id) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/artist/albums/$id', {'limit': 100, 'offset': 0, 'total': true}),
      () => c.plainGet('/artist/albums/$id', {'limit': 100, 'offset': 0, 'total': true}),
      () => c.weapi('/artist/album', {'id': id, 'limit': 100, 'offset': 0}),
      () => c.publicPlainGet('/artist/album', {'id': id, 'limit': 100, 'offset': 0}),
      () => c.publicPlainGet('/artist/albums', {'id': id, 'limit': 100, 'offset': 0}),
      () => c.plainGet('/artist/album', {'id': id, 'limit': 100, 'offset': 0}),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final data = _mapJsonString(j['data']);
        final raw = j['hotAlbums'] ?? j['albums'] ??
            data?['hotAlbums'] ?? data?['albums'] ??
            data?['hotAlbum'];
        final values = (raw is List ? raw : const [])
            .whereType<Map>()
            .map((e) => AlbumSummary.fromJson(Map<String, dynamic>.from(e)))
            .where((a) => a.id > 0)
            .toList();
        if (values.isNotEmpty || raw is List) return values;
      } catch (_) {}
    }
    return const [];
  }

  Future<List<Track>> artistTopSongs(int id) async {
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/artist/top/song', {'id': id}),
      () => c.plainGet('/artist/top/song', {'id': id}),
      () => c.publicPlainGet('/artist/top/song', {'id': id}),
      () => c.weapi('/artist/songs', {'id': id, 'limit': 50, 'offset': 0, 'order': 'hot'}),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final nested = _mapJsonString(j['data']);
        final rawSongs = j['songs'] ?? (nested != null ? nested['songs'] : null) ?? j['result'];
        final tracks = decodeTracks(rawSongs);
        if (tracks.isNotEmpty) return await enrichTracksMetadata(tracks);
      } catch (_) {}
    }
    return const [];
  }

  Future<List<Track>> artistSongs(int id, {int limit = 100, int offset = 0}) async {
    final payload = {'id': id, 'limit': limit, 'offset': offset, 'order': 'hot'};
    final requests = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/artist/songs', payload),
      () => c.plainGet('/artist/songs', payload),
      () => c.publicPlainGet('/artist/songs', payload),
    ];
    for (final request in requests) {
      try {
        final j = await request().timeout(const Duration(seconds: 8));
        final nested = _mapJsonString(j['data']);
        final rawSongs = j['songs'] ?? (nested != null ? nested['songs'] : null) ?? j['result'];
        final tracks = decodeTracks(rawSongs);
        if (tracks.isNotEmpty) return await enrichTracksMetadata(tracks);
      } catch (_) {}
    }
    return const [];
  }

  SearchResult? _parseSearch(Map<String, dynamic> j) {
    Map<String, dynamic>? r;
    if (j['result'] is Map) {
      r = Map<String, dynamic>.from(j['result'] as Map);
    } else if (_mapJsonString(j['data']) != null) {
      final data = _mapJsonString(j['data'])!;
      r = data['result'] is Map
          ? Map<String, dynamic>.from(data['result'] as Map)
          : data;
    }
    if (r == null) return null;
    final parsed = SearchResult(
      songs: decodeTracks(r['songs']),
      albums: (r['albums'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => AlbumSummary.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.id > 0)
          .toList(),
      artists: (r['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ArtistSummary.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.id > 0)
          .toList(),
      playlists: (r['playlists'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PlaylistSummary.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.id > 0)
          .toList(),
    );
    return (parsed.songs.isNotEmpty || parsed.albums.isNotEmpty ||
            parsed.artists.isNotEmpty || parsed.playlists.isNotEmpty)
        ? parsed
        : null;
  }

  Future<SearchResult> search(
    String keywords,
    SearchType type, {
    int limit = 30,
    int offset = 0,
  }) async {
    final query = keywords.trim();
    if (query.isEmpty) return const SearchResult();

    // Match iOS: /eapi/cloudsearch/pc is the primary search contract.
    // Do not send HTML highlight tags; they are unnecessary for our parser and
    // have caused otherwise valid desktop-search responses to be rejected.
    final payload = <String, dynamic>{
      's': query,
      'type': type.value,
      'limit': limit,
      'offset': offset,
      'total': true,
    };
    await c.ensureGuestSession();

    final candidates = <Future<Map<String, dynamic>> Function()>[
      // Same contract as the iOS app.
      () => c.eapi('/cloudsearch/pc', payload),
      // Common server-side compatibility routes.
      () => c.weapi('/cloudsearch/pc', payload),
      () => c.weapi('/cloudsearch', payload),
      () => c.weapi('/cloudsearch/get/web', payload),
      () => c.publicWeapi('/cloudsearch/pc', payload),
      () => c.publicPlainGet('/cloudsearch/pc', payload),
      () => c.publicPlainGet('/cloudsearch', payload),
      () => c.publicPlainPost('/cloudsearch/pc', payload),
      () => c.publicPlainPost('/search/get', payload),
      () => c.publicPlainGet('/search/get', payload),
      () => c.plainPost('/search/get/web', payload),
    ];
    for (final request in candidates) {
      try {
        final parsed = _parseSearch(await request());
        if (parsed != null) {
          if (type == SearchType.playlists) {
            // Search may return dozens of playlists. Hydrate only the first
            // visible batch; Artwork itself also has an on-demand resolver so
            // scrolling later rows can fetch their covers without issuing a
            // burst of requests for all 50 results.
            final head = parsed.playlists.take(8).toList();
            final hydrated = await refreshPlaylistCovers(head);
            final coversById = <int, String?>{
              for (final playlist in hydrated) playlist.id: playlist.coverUrl,
            };
            final merged = parsed.playlists.map((playlist) {
              final cover = coversById[playlist.id];
              return cover != null && cover.isNotEmpty
                  ? playlist.copyWith(coverUrl: cover)
                  : playlist;
            }).toList();
            return SearchResult(songs: parsed.songs, albums: parsed.albums, artists: parsed.artists, playlists: merged);
          }
          return parsed;
        }
      } catch (_) {}
    }
    return const SearchResult();
  }

  Future<String?> defaultKeyword() async {final j=await c.eapi('/search/defaultkeyword/get');final d=j['data'];return d is Map?asString(d['showKeyword']):null;}

  Future<List<SongUrlData>> songUrl(List<int> ids, String level) async {
    if (ids.isEmpty) return const [];
    final idString = '[${ids.join(',')}]';
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.eapi('/song/enhance/player/url/v1', {
        'ids': idString,
        'level': level,
        'encodeType': 'flac',
        if (level == 'sky') 'immerseType': 'c51',
      }),
      () => c.eapi('/song/enhance/player/url', {
        'ids': idString,
        'br': _bitrateFor(level),
      }),
      () => c.weapi('/song/enhance/player/url', {
        'ids': idString,
        'br': _bitrateFor(level),
      }),
      () => c.eapi('/song/url', {
        'ids': idString,
        'br': _bitrateFor(level),
      }),
      () => c.weapi('/song/url', {
        'ids': idString,
        'br': _bitrateFor(level),
      }),
    ];
    for (final request in candidates) {
      try {
        final j = await request();
        final data = j['data'];
        final items = (data is List ? data : const [])
            .whereType<Map>()
            .map((e) => SongUrlData.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (items.any((e) => e.url != null && e.url!.isNotEmpty)) {
          return items;
        }
        if (items.isNotEmpty) return items;
      } catch (_) {}
    }
    return const [];
  }

  int _bitrateFor(String level) {
    switch (level) {
      case 'standard':
        return 128000;
      case 'higher':
        return 192000;
      case 'exhigh':
        return 320000;
      default:
        return 999000;
    }
  }
  Future<LyricResponse> lyric(int id) async {
    // The iOS client uses lyric/v1 first so yrc/word timing is available.
    final candidates = <Future<Map<String, dynamic>> Function()>[
      () => c.weapi('/song/lyric/v1', {
        'id': id, 'cp': false, 'lv': 0, 'kv': 0, 'tv': 0, 'rv': 0,
        'yv': 0, 'ytv': 0, 'yrv': 0,
      }),
      () => c.weapi('/song/lyric', {'id': id, 'lv': -1, 'kv': -1, 'tv': -1, 'rv': -1}),
      () => c.publicPlainGet('/song/lyric', {'id': id, 'lv': -1, 'kv': -1, 'tv': -1, 'rv': -1}),
      () => c.plainGet('/song/lyric', {'id': id, 'lv': -1, 'kv': -1, 'tv': -1, 'rv': -1}),
    ];
    LyricResponse? fallback;
    LyricResponse? bestLineLevel;
    for (final request in candidates) {
      try {
        final r = LyricResponse.fromJson(await request());
        fallback ??= r;
        // YRC is an optional enhancement. Preserve the original lyric
        // behavior: as soon as an API response contains either a usable LRC
        // or a usable YRC, return it. LyricsParser will prefer YRC when it
        // can parse it, and otherwise fall back to the ordinary LRC lines.
        if ((r.yrc ?? '').trim().isNotEmpty ||
            (r.lrc ?? '').trim().isNotEmpty) {
          return r;
        }
      } catch (_) {}
    }
    return fallback ?? bestLineLevel ?? const LyricResponse();
  }

  Future<int?> createPlaylist(String name, {bool isPrivate = false}) async {
    final j = await c.weapi('/playlist/create', {
      'name': name,
      'privacy': isPrivate ? 10 : 0,
      'type': 'NORMAL',
    });
    final id = asInt(j['id']);
    return id > 0 ? id : null;
  }

  Future<void> deletePlaylist(int id) async {
    await c.weapi('/playlist/remove', {'ids': '[$id]'});
  }

  Future<void> subscribePlaylist(int id, bool sub) async {
    Object primaryError = const NeteaseException('收藏歌单失败');

    // Match the original: EAPI with a coherent persisted desktop identity.
    try {
      await c.accountEapi(
        '/playlist/${sub ? 'subscribe' : 'unsubscribe'}',
        {'id': id},
      );
      return;
    } catch (e) {
      primaryError = e;
    }

    // Android compatibility fallback for gateways that reject the normal
    // mobile request; this remains secondary, never the first write.
    try {
      final result = await c.subscribePlaylistInBrowser(
        id: id,
        subscribe: sub,
      ).timeout(const Duration(seconds: 18));
      final code = asInt(result['code'], -1);
      if (result['applied'] == true || code == 200) {
        return;
      }
    } catch (_) {}

    try {
      final antiCheatToken = await c.fetchAntiCheatToken();
      const checkToken =
          '9ca17ae2e6ffcda170e2e6ee8af14fbabdb988f225b3868eb2c15a879b9a83d274a790ac8ff54a97b889d5d42af0feaec3b92af58cff99c470a7eafd88f75e839a9ea7c14e909da883e83fb692a3abdb6b92adee9';
      await c.eapiPc(
        sub ? '/playlist/subscribe' : '/playlist/unsubscribe',
        {
          'id': id,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (sub) 'checkToken': checkToken,
        },
        null,
        antiCheatToken,
      );
      return;
    } catch (_) {
      throw primaryError;
    }
  }

  Future<void> playlistTracks(String op,int playlistId,List<int> ids) async {
    final s='[${ids.join(',')}]';
    try {
      await c.weapi('/playlist/manipulate/tracks',{'op':op,'pid':playlistId,'trackIds':s,'imme':'true'});
    } catch(e) {
      if(op=='add'&&e is NeteaseException&&e.code==512) {
        await c.weapi('/playlist/manipulate/tracks',{'op':op,'pid':playlistId,'trackIds':'[${(ids+ids).join(',')}]','imme':'true'});
      } else {
        rethrow;
      }
    }
  }
}

class QrStatus {
  final int code;
  final String? message, nickname, avatarUrl;
  final UserProfile? profile;
  const QrStatus(this.code, this.message, this.nickname, [this.avatarUrl, this.profile]);
}
class PlaylistDetail { final int id; final String name; final String? cover; final PlaylistCreator? creator; final String? description; final int trackCount,playCount,subscribedCount; final bool subscribed; final List<int> trackIds; final List<Track> tracks;
 const PlaylistDetail({required this.id,required this.name,this.cover,this.creator,this.description,this.trackCount=0,this.playCount=0,this.subscribedCount=0,this.subscribed=false,this.trackIds=const [],this.tracks=const []});
 PlaylistDetail copyWith({String? cover, PlaylistCreator? creator, String? description, int? trackCount, int? playCount, int? subscribedCount, bool? subscribed, List<int>? trackIds, List<Track>? tracks}) => PlaylistDetail(
   id: id, name: name, cover: cover ?? this.cover, creator: creator ?? this.creator, description: description ?? this.description,
   trackCount: trackCount ?? this.trackCount, playCount: playCount ?? this.playCount, subscribedCount: subscribedCount ?? this.subscribedCount,
   subscribed: subscribed ?? this.subscribed, trackIds: trackIds ?? this.trackIds, tracks: tracks ?? this.tracks,
 );
 factory PlaylistDetail.fromJson(Map<String,dynamic> j) {
   final tracks = decodeTracks(j['tracks']);
   final cover = asUrlString(j['coverImgUrl']) ??
       asUrlString(j['picUrl']) ??
       asUrlString(j['coverUrl']) ??
       asUrlString(j['cover']) ??
       asUrlString(j['imgUrl']) ??
       tracks.firstOrNull?.album.picUrl;
   return PlaylistDetail(
     id: asInt(j['id']),
     name: asString(j['name']) ?? '',
     cover: cover,
     creator: j['creator'] is Map ? PlaylistCreator.fromJson(Map<String,dynamic>.from(j['creator'])) : null,
     description: asString(j['description']),
     trackCount: asInt(j['trackCount'] ?? j['track_count']),
     playCount: asInt(j['playCount'] ?? j['play_count']),
     subscribedCount: asInt(j['subscribedCount']),
     subscribed: asBool(j['subscribed']),
     trackIds: (j['trackIds'] as List? ?? const[]).map((e)=>e is Map ? asInt(e['id']) : asInt(e)).where((e)=>e>0).toList(),
     tracks: tracks,
   );
 }
}
class PlaylistDetailResult {final PlaylistDetail playlist;final List<TrackPrivilege> privileges;const PlaylistDetailResult(this.playlist,this.privileges);}
class AlbumDetailResult {final AlbumSummary album;final List<Track> songs;const AlbumDetailResult(this.album,this.songs);}
class ArtistDetailResult {final ArtistSummary artist;final List<Track> hotSongs;const ArtistDetailResult(this.artist,this.hotSongs);}

enum SearchType {all(0),songs(1),albums(10),artists(100),playlists(1000); final int value; const SearchType(this.value);}
class SearchResult {final List<Track> songs;final List<AlbumSummary> albums;final List<ArtistSummary> artists;final List<PlaylistSummary> playlists;const SearchResult({this.songs=const[],this.albums=const[],this.artists=const[],this.playlists=const[]}); bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;}

