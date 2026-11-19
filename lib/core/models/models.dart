import 'dart:convert';

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

String? asString(dynamic v) => v is String && v.isNotEmpty ? v : null;

String? asUrlString(dynamic v) {
  final value = asString(v)?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  if (value.startsWith('https://')) return value;
  return null;
}

class ArtistRef {
  final int id;
  final String name;
  const ArtistRef({required this.id, required this.name});
  factory ArtistRef.fromJson(Map<String, dynamic> j) => ArtistRef(id: asInt(j['id']), name: asString(j['name']) ?? '');
}

class AlbumRef {
  final int id;
  final String name;
  final String? picUrl;
  const AlbumRef({required this.id, required this.name, this.picUrl});
  factory AlbumRef.fromJson(Map<String, dynamic> j) => AlbumRef(
    id: asInt(j['id']), name: asString(j['name']) ?? '', picUrl:
      asUrlString(j['picUrl']) ?? asUrlString(j['picUrlStr']) ?? asUrlString(j['picUrl120']) ??
      asUrlString(j['cover']) ?? asUrlString(j['coverUrl']) ?? asUrlString(j['img1v1Url']),
  );
}

class TrackPrivilege {
  final int id; final int? fee; final int? pl; final int? st; final bool? cs; final int? maxbr;
  const TrackPrivilege({required this.id, this.fee, this.pl, this.st, this.cs, this.maxbr});
  factory TrackPrivilege.fromJson(Map<String, dynamic> j) => TrackPrivilege(
    id: asInt(j['id']), fee: j['fee'] == null ? null : asInt(j['fee']), pl: j['pl'] == null ? null : asInt(j['pl']),
    st: j['st'] == null ? null : asInt(j['st']), cs: j['cs'] == null ? null : asBool(j['cs']),
    maxbr: j['maxbr'] == null ? null : asInt(j['maxbr']),
  );
}

class Track {
  final int id; final String name; final List<ArtistRef> artists; final AlbumRef album; final int durationMs;
  final List<String> alias; final List<String> transNames; final int fee; final int mvId; final int trackNo;
  final String? disc; final bool noCopyright; final bool isCloud; final TrackPrivilege? privilege;
  const Track({required this.id, required this.name, required this.artists, required this.album, required this.durationMs,
    this.alias = const [], this.transNames = const [], this.fee = 0, this.mvId = 0, this.trackNo = 0, this.disc,
    this.noCopyright = false, this.isCloud = false, this.privilege});
  factory Track.fromJson(Map<String, dynamic> j) {
    final artistsRaw = j['ar'] ?? j['artists'];
    final albumRaw = j['al'] ?? j['album'];
    final artists = artistsRaw is List
        ? artistsRaw
            .whereType<Map>()
            .map((e) => ArtistRef.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ArtistRef>[];
    return Track(
      id: asInt(j['id']), name: asString(j['name']) ?? '',
      artists: artists,
      album: albumRaw is Map ? AlbumRef.fromJson(Map<String,dynamic>.from(albumRaw)) : const AlbumRef(id: 0, name: ''),
      durationMs: asInt(j['dt'] ?? j['duration']),
      alias: ((j['alia'] ?? j['alias']) as List?)?.whereType<String>().toList() ?? const [],
      transNames: (j['tns'] as List?)?.whereType<String>().toList() ?? const [], fee: asInt(j['fee']),
      mvId: asInt(j['mv']), trackNo: asInt(j['no']), disc: asString(j['cd']),
      noCopyright: j.containsKey('noCopyrightRcmd') && j['noCopyrightRcmd'] != null,
      isCloud: j.containsKey('pc') && j['pc'] != null,
      privilege: j['privilege'] is Map ? TrackPrivilege.fromJson(Map<String,dynamic>.from(j['privilege'])) : null,
    );
  }
  String get artistNames => artists.map((e) => e.name).join(' / ');
  Duration get duration => Duration(milliseconds: durationMs);
  Track copyWith({AlbumRef? album, List<ArtistRef>? artists}) => Track(
    id: id, name: name, artists: artists ?? this.artists, album: album ?? this.album,
    durationMs: durationMs, alias: alias, transNames: transNames, fee: fee, mvId: mvId,
    trackNo: trackNo, disc: disc, noCopyright: noCopyright, isCloud: isCloud, privilege: privilege,
  );
  String? get subtitle => transNames.isNotEmpty ? transNames.first : (alias.isNotEmpty ? alias.first : null);
  Map<String,dynamic> toJson() => {
    'id': id, 'name': name, 'ar': artists.map((e) => {'id': e.id, 'name': e.name}).toList(),
    'al': {'id': album.id, 'name': album.name, 'picUrl': album.picUrl}, 'dt': durationMs,
    'alia': alias, 'tns': transNames, 'fee': fee, 'mv': mvId, 'no': trackNo, if (disc != null) 'cd': disc,
  };
}

class PlaylistCreator {
  final int userId; final String nickname; final String? avatarUrl;
  const PlaylistCreator({required this.userId, required this.nickname, this.avatarUrl});
  factory PlaylistCreator.fromJson(Map<String,dynamic> j) => PlaylistCreator(userId: asInt(j['userId']), nickname: asString(j['nickname']) ?? '', avatarUrl: asUrlString(j['avatarUrl']));
}

class PlaylistSummary {
  final int id; final String name; final String? coverUrl; final int playCount; final int trackCount;
  final String? copywriter; final PlaylistCreator? creator; final int specialType; final int privacy; final bool subscribed; final List<int> trackIds;
  const PlaylistSummary({required this.id,required this.name,this.coverUrl,this.playCount=0,this.trackCount=0,this.copywriter,this.creator,this.specialType=0,this.privacy=0,this.subscribed=false,this.trackIds=const []});
  factory PlaylistSummary.fromJson(Map<String,dynamic> j) => PlaylistSummary(
    id: asInt(j['id']), name: asString(j['name']) ?? '', coverUrl:
      asUrlString(j['picUrl']) ??
      asUrlString(j['coverImgUrl']) ??
      asUrlString(j['coverImgUrlStr']) ??
      asUrlString(j['picUrlStr']) ??
      asUrlString(j['cover']) ??
      asUrlString(j['coverUrl']) ??
      asUrlString(j['coverUrlStr']) ??
      asUrlString(j['imgUrl']) ??
      asUrlString(j['imageUrl']) ??
      asUrlString(j['picUrl120']) ??
      asUrlString(j['coverUrl120']) ??
      asUrlString(j['picUrl300']) ??
      asUrlString(j['img1v1Url']),
    playCount: asInt(j['playCount'] ?? j['playcount']), trackCount: asInt(j['trackCount'] ?? j['track_count']), copywriter: asString(j['copywriter']),
    creator: j['creator'] is Map ? PlaylistCreator.fromJson(Map<String,dynamic>.from(j['creator'])) : null,
    specialType: asInt(j['specialType']), privacy: asInt(j['privacy']), subscribed: asBool(j['subscribed']),
    trackIds: (j['trackIds'] as List? ?? const []).map((e) => e is Map ? asInt(e['id']) : asInt(e)).where((e) => e > 0).toList(),
  );
  PlaylistSummary copyWith({String? coverUrl, String? name, int? playCount, int? trackCount, String? copywriter, PlaylistCreator? creator, List<int>? trackIds}) => PlaylistSummary(
    id: id, name: name ?? this.name, coverUrl: coverUrl ?? this.coverUrl, playCount: playCount ?? this.playCount, trackCount: trackCount ?? this.trackCount,
    copywriter: copywriter ?? this.copywriter, creator: creator ?? this.creator, specialType: specialType, privacy: privacy, subscribed: subscribed, trackIds: trackIds ?? this.trackIds,
  );
  bool get isLikedSongsList =>
      specialType == 5 ||
      name.trim() == '我喜欢的音乐' ||
      name.trim().toLowerCase() == 'liked songs';
}

class UserProfile {
  final int userId; final String nickname; final String? avatarUrl; final String? backgroundUrl; final String? signature; final int vipType;
  const UserProfile({required this.userId,required this.nickname,this.avatarUrl,this.backgroundUrl,this.signature,this.vipType=0});
  factory UserProfile.fromJson(Map<String,dynamic> j) => UserProfile(
    userId: asInt(j['userId'] ?? j['id']),
    nickname: asString(j['nickname'] ?? j['userName'] ?? j['username']) ?? '',
    avatarUrl: asUrlString(j['avatarUrl']) ?? asUrlString(j['avatarUrl120']) ?? asUrlString(j['avatarUrlStr']) ?? asUrlString(j['avatar']) ?? asUrlString(j['userAvatar']) ?? asUrlString(j['userPicUrl']),
    backgroundUrl: asUrlString(j['backgroundUrl']) ?? asUrlString(j['background']),
    signature: asString(j['signature']),
    vipType: asInt(j['vipType']),
  );

  UserProfile copyWith({
    int? userId,
    String? nickname,
    String? avatarUrl,
    String? backgroundUrl,
    String? signature,
    int? vipType,
  }) => UserProfile(
    userId: userId ?? this.userId,
    nickname: nickname ?? this.nickname,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    backgroundUrl: backgroundUrl ?? this.backgroundUrl,
    signature: signature ?? this.signature,
    vipType: vipType ?? this.vipType,
  );
}

class AlbumSummary { final int id; final String name; final String? picUrl; final String artistName; final int publishTime; final int size; final String? subType; final List<String> alias;
  const AlbumSummary({required this.id,required this.name,this.picUrl,this.artistName='',this.publishTime=0,this.size=0,this.subType,this.alias=const []});
  factory AlbumSummary.fromJson(Map<String,dynamic> j) { final a=j['artist'] is Map ? asString(j['artist']['name']) : null; final list=j['artists'] as List?;
    return AlbumSummary(id:asInt(j['id']),name:asString(j['name'])??'',picUrl:asUrlString(j['picUrl'])??asUrlString(j['cover'])??asUrlString(j['coverImgUrl'])??asUrlString(j['coverUrl'])??asUrlString(j['imgUrl']),artistName:a??(list?.whereType<Map>().map((e)=>asString(e['name'])).whereType<String>().join(' / ')??''),publishTime:asInt(j['publishTime']),size:asInt(j['size']),subType:asString(j['subType']),alias: ((j['alia'] ?? j['alias']) as List?)?.whereType<String>().toList() ?? const []);
  }
}

class ArtistSummary { final int id; final String name; final String? picUrl; final int albumSize; final int musicSize; final String? briefDesc; final List<String> alias; final bool followed;
  const ArtistSummary({required this.id,required this.name,this.picUrl,this.albumSize=0,this.musicSize=0,this.briefDesc,this.alias=const [],this.followed=false});
  factory ArtistSummary.fromJson(Map<String,dynamic> j)=>ArtistSummary(id:asInt(j['id']),name:asString(j['name'])??'',picUrl:asString(j['picUrl'])??asString(j['cover'])??asString(j['avatar'])??asString(j['img1v1Url'])??asString(j['img1v1Url120']),albumSize:asInt(j['albumSize']),musicSize:asInt(j['musicSize']),briefDesc:asString(j['briefDesc']),alias:(j['alias'] as List?)?.whereType<String>().toList()??const [],followed:asBool(j['followed']));
}

class ToplistTrackPreview {
  final String first;
  final String second;

  const ToplistTrackPreview({required this.first, required this.second});

  factory ToplistTrackPreview.fromJson(Map<String, dynamic> j) =>
      ToplistTrackPreview(
        first: asString(j['first']) ?? '',
        second: asString(j['second']) ?? '',
      );
}

class ToplistItem {
  final int id;
  final String name;
  final String? coverImgUrl;
  final String? updateFrequency;
  final List<ToplistTrackPreview> tracks;
  final int playCount;

  const ToplistItem({
    required this.id,
    required this.name,
    this.coverImgUrl,
    this.updateFrequency,
    this.tracks = const [],
    this.playCount = 0,
  });

  factory ToplistItem.fromJson(Map<String, dynamic> j) => ToplistItem(
        id: asInt(j['id']),
        name: asString(j['name']) ?? '',
        coverImgUrl: asString(j['coverImgUrl']) ??
            asString(j['picUrl']) ??
            asString(j['cover']) ??
            asString(j['coverUrl']),
        updateFrequency: asString(j['updateFrequency']),
        tracks: (j['tracks'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    ToplistTrackPreview.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        playCount: asInt(j['playCount']),
      );
}

class PlayRecordItem {
  final Track song;
  final int playCount;
  const PlayRecordItem({required this.song, this.playCount = 0});

  factory PlayRecordItem.fromJson(Map<String, dynamic> j) {
    final raw = j['song'] ?? j['simpleSong'] ?? j['track'];
    final song = raw is Map
        ? Track.fromJson(Map<String, dynamic>.from(raw))
        : Track.fromJson(j);
    return PlayRecordItem(song: song, playCount: asInt(j['playCount'] ?? j['playcount']));
  }
}

class CloudSongItem {
  final Track? simpleSong;
  final int songId;
  final String? fileName;
  final int fileSize;

  const CloudSongItem({this.simpleSong, this.songId = 0, this.fileName, this.fileSize = 0});

  factory CloudSongItem.fromJson(Map<String, dynamic> j) {
    final raw = j['simpleSong'] ?? j['song'] ?? j['simple_song'];
    Track? track;
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      track = Track.fromJson(m);
    } else {
      // Legacy cloud responses expose song metadata at the top level.
      final artistsRaw = j['artists'] ?? j['ar'];
      final albumRaw = j['album'] ?? j['al'];
      final normalized = <String, dynamic>{
        ...j,
        'id': j['songId'] ?? j['id'],
        'name': j['songName'] ?? j['name'] ?? j['fileName'],
        'ar': artistsRaw,
        'al': albumRaw,
        'dt': j['duration'] ?? j['dt'],
      };
      track = Track.fromJson(normalized);
    }
    return CloudSongItem(
      simpleSong: track.id > 0 && track.name.isNotEmpty ? track : null,
      songId: asInt(j['songId'] ?? j['id']),
      fileName: asString(j['fileName'] ?? j['fileNameStr']),
      fileSize: asInt(j['fileSize'] ?? j['size']),
    );
  }
}

class CloudSongsResult {
  final List<CloudSongItem> items;
  final bool hasMore;
  final int? size;
  final int? maxSize;
  const CloudSongsResult({required this.items, this.hasMore = false, this.size, this.maxSize});
}

class LyricBody { final String? lyric; const LyricBody(this.lyric); }
class LyricResponse {
  final String? lrc, tlyric, romalrc, yrc, ytlrc, yromalrc;
  const LyricResponse({this.lrc, this.tlyric, this.romalrc, this.yrc, this.ytlrc, this.yromalrc});

  static String? _body(dynamic value) {
    if (value is Map) return asString(value['lyric'] ?? value['text']);
    if (value is String) return value;
    return null;
  }

  factory LyricResponse.fromJson(Map<String,dynamic> j) => LyricResponse(
    lrc: _body(j['lrc']),
    tlyric: _body(j['tlyric']),
    romalrc: _body(j['romalrc']),
    yrc: _body(j['yrc']),
    ytlrc: _body(j['ytlrc']),
    yromalrc: _body(j['yromalrc']),
  );
}

class SongUrlData {
  final int id;
  final String? url;
  final int br;
  final int size;
  final String? type, level;
  final int fee;
  final bool freeTrial;

  const SongUrlData({
    required this.id,
    this.url,
    this.br = 0,
    this.size = 0,
    this.type,
    this.level,
    this.fee = 0,
    this.freeTrial = false,
  });

  factory SongUrlData.fromJson(Map<String, dynamic> j) => SongUrlData(
        id: asInt(j['id']),
        url: asString(j['url']),
        br: asInt(j['br']),
        size: asInt(j['size']),
        type: asString(j['type']),
        level: asString(j['level']),
        fee: asInt(j['fee']),
        freeTrial: j['freeTrialInfo'] != null,
      );
}

String resizedImageUrl(String? raw, [int size=512]) {
  if (raw == null || raw.isEmpty) return '';
  final s = raw.replaceFirst('http://','https://');
  return '$s${s.contains('?') ? '&' : '?'}param=${size}y$size';
}

String formatCount(int count) { if (count>=100000000) return '${(count/10000000).round()/10}亿'; if(count>=10000)return '${(count/1000).round()/10}万'; return '$count'; }
String formatDuration(Duration d)=>'${d.inMinutes}:${(d.inSeconds%60).toString().padLeft(2,'0')}';

List<Track> decodeTracks(dynamic v) {
  if (v is! List) return <Track>[];
  final out = <Track>[];
  for (final raw in v) {
    if (raw is! Map) continue;
    try {
      final track = Track.fromJson(Map<String, dynamic>.from(raw));
      if (track.id > 0 && track.name.isNotEmpty) out.add(track);
    } catch (_) {}
  }
  return out;
}
Map<String,dynamic> object(dynamic v)=>v is Map?Map<String,dynamic>.from(v):<String,dynamic>{};

String jsonString(dynamic value) => jsonEncode(value);
