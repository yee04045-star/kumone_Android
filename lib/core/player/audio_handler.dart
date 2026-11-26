import 'dart:async';
import 'dart:convert';
import 'crossfade_curve.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/netease_api.dart';
import '../models/models.dart';
import '../unblock/unblock_service.dart';

class KumoneAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayer _player = AudioPlayer();
  AudioPlayer? _outgoing;
  AudioPlayer? _preparing;
  Timer? _fadeTimer;
  bool _preparingFade = false;
  int crossfadeSeconds = 0;
  bool exclusiveUsb = false;
  double _masterVolume = 1;
  double _fadeProgress = 0;
  int _fadeElapsedMs = 0;
  int? _attemptedFadeGeneration;
  final List<Track> _tracks = [];
  final List<Track> _playNext = [];
  int _index = -1;
  String quality = 'exhigh';
  bool unblock = true;
  StreamSubscription? _position;
  StreamSubscription? _playerState;
  final StreamController<String> _sourceNoticeController =
      StreamController<String>.broadcast();
  final Map<String, CachedAudio> _preloadedAudio = {};
  final Map<String, Future<CachedAudio?>> _preloadFutures = {};
  int _loadGeneration = 0;
  int _preloadGeneration = 0;
  int _scrobbleTrackId = 0;
  bool _scrobbleStarted = false;
  bool _scrobbleFinished = false;
  String? _activeLocalAudioPath;
  static const _persistKey = 'kumone.playback_queue.v1';

  Stream<String> get sourceNotices => _sourceNoticeController.stream;


  double get volume => _masterVolume;

  Future<void> setVolume(double value) async {
    final safe = value.clamp(0.0, 1.0).toDouble();
    _masterVolume = safe;
    final outgoing = _outgoing;
    if (outgoing == null) {
      await _player.setVolume(safe);
    } else {
      final gains = crossfadeGains(_fadeProgress, safe);
      await Future.wait(
          [outgoing.setVolume(gains.$1), _player.setVolume(gains.$2)]);
    }
  }

  void _emitSourceNotice(String source) {
    if (source.trim().isEmpty || source == 'NetEase') return;
    _sourceNoticeController.add('已使用第三方音源：$source');
  }

  KumoneAudioHandler() {
    _bindPlayer();
  }

  void _bindPlayer() {
    unawaited(_position?.cancel());
    unawaited(_playerState?.cancel());
    _position = _player.positionStream.listen((position) {
      _broadcastPosition(position);
      if (!_preparingFade &&
          _outgoing == null &&
          crossfadeSeconds > 0 &&
          !exclusiveUsb &&
          _player.playing &&
          _player.duration != null &&
          _player.processingState == ProcessingState.ready) {
        final remaining = _player.duration! - position;
        if (remaining > Duration.zero &&
            remaining <= Duration(seconds: crossfadeSeconds) &&
            _nextTrackForPreload() != null) {
          unawaited(_tryCrossfade());
        }
      }
    });
    _playerState = _player.playerStateStream.listen((s) {
      _broadcastState(s.processingState);
      if (s.processingState == ProcessingState.completed &&
          _player.loopMode != LoopMode.one) {
        _finishScrobble(completed: true);
        unawaited(skipToNext());
      }
    });
  }

  void _broadcastState(ProcessingState processingState) {
    final current = playbackState.value;
    playbackState.add(
      current.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.playPause,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapState(processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _index < 0 ? null : _index,
      ),
    );
  }

  AudioProcessingState _mapState(ProcessingState state) => switch (state) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

  void _broadcastPosition(Duration position) {
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: position,
        bufferedPosition: _player.bufferedPosition,
        queueIndex: _index < 0 ? null : _index,
      ),
    );
  }

  Future<void> setTracks(
    List<Track> tracks, {
    int index = 0,
    bool autoplay = true,
  }) async {
    _finishScrobble();
    _scrobbleTrackId = 0;
    _scrobbleStarted = false;
    _scrobbleFinished = false;
    _tracks
      ..clear()
      ..addAll(tracks);
    _playNext.clear();
    _index = _tracks.isEmpty ? -1 : index.clamp(0, _tracks.length - 1).toInt();
    queue.add(_tracks.map(_mediaItem).toList(growable: false));
    if (_index >= 0) mediaItem.add(_mediaItem(_tracks[_index]));
    unawaited(_persistQueue());
    if (_index >= 0) unawaited(_loadCurrent(autoplay: autoplay));
  }

  Future<void> restorePersistedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final tracksRaw = decoded['tracks'];
      final nextRaw = decoded['playNext'];
      if (tracksRaw is! List) return;
      _tracks
        ..clear()
        ..addAll(
          tracksRaw
              .whereType<Map>()
              .map((e) => Track.fromJson(Map<String, dynamic>.from(e))),
        );
      _playNext
        ..clear()
        ..addAll(
          nextRaw is List
              ? nextRaw
                  .whereType<Map>()
                  .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
              : const <Track>[],
        );
      final savedIndex = decoded['index'];
      _index = _tracks.isEmpty
          ? -1
          : (savedIndex is num ? savedIndex.toInt() : 0)
              .clamp(0, _tracks.length - 1)
              .toInt();
      queue.add(_tracks.map(_mediaItem).toList(growable: false));
      if (_index >= 0) mediaItem.add(_mediaItem(_tracks[_index]));
      _broadcastState(_player.processingState);
    } catch (_) {
      // Corrupt queue snapshots are ignored; playback can start from a new queue.
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _persistKey,
        jsonEncode({
          'tracks': _tracks.map((e) => e.toJson()).toList(),
          'playNext': _playNext.map((e) => e.toJson()).toList(),
          'index': _index,
        }),
      );
    } catch (_) {}
  }

  Uri? _httpsUri(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var value = raw.trim();
    if (value.startsWith('//')) value = 'https:$value';
    if (value.startsWith('http://')) value = 'https://${value.substring(7)}';
    return Uri.tryParse(value);
  }

  Map<String, String> _headersFor(ResolvedAudio resolved) => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36',
        ...resolved.headers,
      };

  Future<AudioSource> _audioSourceFor(ResolvedAudio resolved, Track track) async {
    if (resolved.isLocalFile) {
      return AudioSource.file(resolved.url.toFilePath());
    }
    final file = await UnblockService.streamingCacheFile(track, quality, resolved.source, resolved.url);
    // just_audio experimental streaming cache avoids a second full download.
    // ignore: experimental_member_use
    return LockCachingAudioSource(resolved.url,
      headers: _headersFor(resolved), cacheFile: file);
  }

  MediaItem _mediaItem(Track t) => MediaItem(
        id: '${t.id}',
        title: t.name,
        artist: t.artistNames,
        album: t.album.name,
        artUri: _httpsUri(t.album.picUrl),
        duration: t.duration,
        extras: {'track': t.toJson()},
      );

  void _resetScrobbleForTrack(Track track, {bool force = false}) {
    if (!force && _scrobbleTrackId == track.id) return;
    _scrobbleTrackId = track.id;
    _scrobbleStarted = false;
    _scrobbleFinished = false;
  }

  void _beginScrobble(Track track) {
    _resetScrobbleForTrack(track);
    if (_scrobbleStarted) return;
    _scrobbleStarted = true;
    unawaited(NeteaseApi.instance.scrobbleStart(trackId: track.id));
  }

  void _finishScrobble({bool completed = false}) {
    if (_scrobbleTrackId <= 0 ||
        !_scrobbleStarted ||
        _scrobbleFinished ||
        _index < 0 ||
        _index >= _tracks.length) {
      return;
    }
    final seconds = _player.position.inSeconds;
    if (seconds <= 1) return;
    final trackId = _tracks[_index].id;
    if (trackId != _scrobbleTrackId) return;
    _scrobbleFinished = true;
    unawaited(NeteaseApi.instance.scrobbleFinish(
        trackId: trackId, seconds: seconds, completed: completed));
  }

  String _preloadKey(Track track) => '${track.id}|$quality';

  Track? _nextTrackForPreload() {
    if (_index < 0 || _index >= _tracks.length) return null;
    if (_player.loopMode == LoopMode.one) return null;

    final currentId = _tracks[_index].id;
    if (_playNext.isNotEmpty) {
      final next = _playNext.first;
      return next.id == currentId ? null : next;
    }
    if (_index + 1 < _tracks.length) {
      final next = _tracks[_index + 1];
      return next.id == currentId ? null : next;
    }
    if (playbackState.value.repeatMode == AudioServiceRepeatMode.all &&
        _tracks.length > 1) {
      return _tracks.first.id == currentId ? null : _tracks.first;
    }
    return null;
  }

  bool _isThirdPartySource(String source) => source != 'NetEase';

  bool Function()? hasVipAccount;

  Future<ResolvedAudio?> _resolveAudio(Track track) async {
    final membershipTrack = track.fee == 1 || track.privilege?.fee == 1;
    if (unblock && membershipTrack && !(hasVipAccount?.call() ?? false)) {
      return UnblockService.resolve(track);
    }
    ResolvedAudio? resolved;
    SongUrlData? official;
    try {
      // NetEase 只做一次完整解析：当前音质不可播就立即进入第三方音源链，
      // 不再额外请求一次 standard，避免播放前产生第二轮等待。
      final urls = await NeteaseApi.instance.songUrl([track.id], quality);
      official = _firstUrl(urls);
      if (official?.url != null &&
          official!.url!.isNotEmpty &&
          !official.freeTrial) {
        resolved = ResolvedAudio(Uri.parse(official.url!), 'NetEase');
      }
    } catch (_) {}

    if ((resolved == null || official?.freeTrial == true) && unblock) {
      try {
        resolved = await UnblockService.resolve(track);
      } catch (_) {}
    }
    return resolved;
  }

  Future<CachedAudio?> _preloadTrack(Track track, int generation) async {
    if (generation != _preloadGeneration) return null;
    final key = _preloadKey(track);

    final memory = _preloadedAudio[key];
    if (memory != null) {
      try {
        if (await memory.file.exists() && await memory.file.length() > 0 &&
          DateTime.now().difference(await memory.file.lastModified()) <= UnblockService.audioCacheLifetime) {
          if (!_isThirdPartySource(memory.source) || unblock) return memory;
        }
      } catch (_) {}
      _preloadedAudio.remove(key);
    }

    final disk = await UnblockService.findCachedAudio(
      track: track,
      quality: quality,
      allowThirdParty: unblock,
    );
    if (generation != _preloadGeneration) return null;
    if (disk != null) {
      _preloadedAudio[key] = disk;
      return disk;
    }

    final resolved = await _resolveAudio(track);
    if (generation != _preloadGeneration || resolved == null) return null;

    final cached = await UnblockService.cacheResolvedAudio(
      track: track,
      quality: quality,
      resolved: resolved,
    );
    if (generation != _preloadGeneration || cached == null) return null;
    if (_isThirdPartySource(cached.source) && !unblock) return null;
    _preloadedAudio[key] = cached;
    return cached;
  }

  Future<CachedAudio?> _preloadNext() async {
    if (!_player.playing || _index < 0 || _tracks.isEmpty) return null;
    final track = _nextTrackForPreload();
    if (track == null) return null;
    final key = _preloadKey(track);
    final existing = _preloadFutures[key];
    if (existing != null) return existing;

    final generation = _preloadGeneration;
    final future = _preloadTrack(track, generation);
    _preloadFutures[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_preloadFutures[key], future)) {
        _preloadFutures.remove(key);
      }
    }
  }

  Future<ResolvedAudio?> _preloadedAudioFor(Track track) async {
    final key = _preloadKey(track);
    final memory = _preloadedAudio[key];
    if (memory != null) {
      try {
        if (await memory.file.exists() && await memory.file.length() > 0 &&
          DateTime.now().difference(await memory.file.lastModified()) <= UnblockService.audioCacheLifetime) {
          if (!_isThirdPartySource(memory.source) || unblock) {
            return ResolvedAudio(Uri.file(memory.file.path), memory.source);
          }
        }
      } catch (_) {}
      _preloadedAudio.remove(key);
    }

    final inflight = _preloadFutures[key];
    if (inflight != null) {
      final cached = await inflight;
      if (cached != null &&
          (unblock || !_isThirdPartySource(cached.source)) &&
          await cached.file.exists() &&
          await cached.file.length() > 0) {
        _preloadedAudio[key] = cached;
        return ResolvedAudio(Uri.file(cached.file.path), cached.source);
      }
    }

    final disk = await UnblockService.findCachedAudio(
      track: track,
      quality: quality,
      allowThirdParty: unblock,
    );
    if (disk == null) return null;
    _preloadedAudio[key] = disk;
    return ResolvedAudio(Uri.file(disk.file.path), disk.source);
  }

  Future<void> _startCurrentPlayback(Track track) async {
    unawaited(_player.play());
    _beginScrobble(track);
    unawaited(_preloadNext());
  }

  Future<void> configureCrossfade(int seconds, bool usb) async {
    crossfadeSeconds = seconds.clamp(0, 12);
    exclusiveUsb = usb;
    if (seconds == 0 || usb) {
      ++_loadGeneration;
      await _cancelCrossfade();
    }
  }

  Future<void> _cancelCrossfade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final old = _outgoing;
    _outgoing = null;
    final preparing = _preparing;
    _preparing = null;
    if (old != null) await old.dispose();
    if (preparing != null) await preparing.dispose();
    _fadeProgress = 0;
    await _player.setVolume(_masterVolume);
  }

  Future<void> _tryCrossfade() async {
    final next = _nextTrackForPreload();
    if (next == null || _preparingFade || exclusiveUsb ||
        _attemptedFadeGeneration == _loadGeneration) {
      return;
    }
    _preparingFade = true;
    final generation = _loadGeneration;
    _attemptedFadeGeneration = generation;
    AudioPlayer? standby;
    try {
      var resolved = await _preloadedAudioFor(next);
      resolved ??= await _resolveAudio(next);
      if (resolved == null || generation != _loadGeneration || !_player.playing) {
        return;
      }
      standby = AudioPlayer();
      _preparing = standby;
      await standby.setVolume(0);
      await standby.setAudioSource(await _audioSourceFor(resolved, next));
      if (generation != _loadGeneration ||
          exclusiveUsb ||
          !_player.playing ||
          _nextTrackForPreload()?.id != next.id) {
        return;
      }
      final remaining = (_player.duration ?? Duration.zero) - _player.position;
      final incomingDuration = standby.duration ?? next.duration;
      final durationMs = [
        crossfadeSeconds * 1000,
        remaining.inMilliseconds,
        incomingDuration.inMilliseconds ~/ 2
      ].reduce((a, b) => a < b ? a : b);
      if (durationMs < 250) return;
      _finishScrobble(completed: true);
      ++_loadGeneration;
      _outgoing = _player;
      _player = standby;
      standby = null;
      _preparing = null;
      if (_playNext.isNotEmpty && _playNext.first.id == next.id) {
        _tracks.insert(_index + 1, _playNext.removeAt(0));
        _index++;
        queue.add(_tracks.map(_mediaItem).toList(growable: false));
      } else {
        _index = (_index + 1) % _tracks.length;
      }
      _resetScrobbleForTrack(next);
      mediaItem.add(_mediaItem(next));
      _activeLocalAudioPath =
          resolved.isLocalFile ? resolved.url.toFilePath() : null;
      _bindPlayer();
      unawaited(_player.play());
      _beginScrobble(next);
      unawaited(_persistQueue());
      _fadeElapsedMs = 0;
      _fadeProgress = 0;
      final incoming = _player;
      final outgoing = _outgoing;
      var applying = false;
      _fadeTimer = Timer.periodic(const Duration(milliseconds: 40), (_) async {
        if (applying ||
            !identical(incoming, _player) ||
            !identical(outgoing, _outgoing) ||
            !_player.playing ||
            _outgoing == null) {
          return;
        }
        applying = true;
        try {
          // Advance only on audible ticks, so pause freezes the envelope.
          _fadeElapsedMs += 40;
          _fadeProgress = (_fadeElapsedMs / durationMs).clamp(0.0, 1.0);
          final old = _outgoing;
          if (old == null) return;
          final gains = crossfadeGains(_fadeProgress, _masterVolume);
          await Future.wait(
              [old.setVolume(gains.$1), incoming.setVolume(gains.$2)]);
          if (!identical(incoming, _player) || !identical(old, _outgoing)) {
            return;
          }
          if (_fadeProgress >= 1) {
            _fadeTimer?.cancel();
            _fadeTimer = null;
            _outgoing = null;
            await old.dispose();
            unawaited(_preloadNext());
          }
        } catch (_) {
          if (identical(incoming, _player) && identical(outgoing, _outgoing)) {
            await _cancelCrossfade();
          }
        } finally {
          applying = false;
        }
      });
    } catch (_) {
      // Preparation failure leaves the current song playing normally.
    } finally {
      if (standby != null && identical(_preparing, standby)) {
        _preparing = null;
        await standby.dispose();
      }
      _preparingFade = false;
    }
  }

  Future<void> clearAudioCache() async {
    _preloadGeneration++;
    _preloadedAudio.clear();
    _preloadFutures.clear();
    final preserve = <String>{};
    final active = _activeLocalAudioPath;
    if (active != null && active.isNotEmpty) preserve.add(active);
    await UnblockService.clearAudioCache(preserveFiles: preserve);
  }

  Future<void> _loadCurrent({bool autoplay = true}) async {
    if (_index < 0 || _index >= _tracks.length) return;
    final index = _index;
    final generation = ++_loadGeneration;
    await _cancelCrossfade();
    var track = _tracks[index];
    _resetScrobbleForTrack(track);
    bool current() =>
        generation == _loadGeneration &&
        index == _index &&
        index < _tracks.length &&
        _tracks[index].id == track.id;

    if (track.id > 0 && (track.album.picUrl == null ||
        track.album.picUrl!.isEmpty ||
        track.album.name.isEmpty)) {
      try {
        final details = await NeteaseApi.instance.songDetails([track.id]);
        if (!current()) return;
        if (details.isNotEmpty) {
          track = details.first;
          _tracks[index] = track;
          queue.add(_tracks.map(_mediaItem).toList(growable: false));
          mediaItem.add(_mediaItem(track));
          unawaited(_persistQueue());
        }
      } catch (_) {}
    }

    ResolvedAudio? resolved = await _preloadedAudioFor(track);
    if (!current()) return;
    resolved ??= await _resolveAudio(track);
    if (!current()) return;

    if (resolved == null) {
      // Keep the same provider order as iOS; outer/url is only the final public
      // redirect after all explicit sources failed.
      try {
        final outer = Uri.parse(
            'https://music.163.com/song/media/outer/url?id=${track.id}.mp3');
        await _player.setAudioSource(AudioSource.uri(outer, headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36',
        }));
        if (!current()) return;
        mediaItem.add(_mediaItem(track));
        _activeLocalAudioPath = null;
        if (autoplay) {
          await _startCurrentPlayback(track);
        }
      } catch (_) {}
      return;
    }

    if (resolved.source != 'NetEase') _emitSourceNotice(resolved.source);
    try {
      await _player.setAudioSource(
        await _audioSourceFor(resolved, track),
      );
      if (!current()) return;
      mediaItem.add(_mediaItem(track));
      _activeLocalAudioPath =
          resolved.isLocalFile ? resolved.url.toFilePath() : null;
      if (autoplay) {
        await _startCurrentPlayback(track);
      }
    } catch (_) {
      // A nominal NetEase URL can still fail at the device. Retry the external
      // chain once, preserving provider order and notifying the chosen source.
      if (!current() || !unblock) return;
      try {
        var passedFailed = resolved.source == 'NetEase';
        var loaded = false;
        ResolvedAudio? fallback;
        await for (final candidate in UnblockService.candidates(track)) {
          if (!current()) return;
          if (!passedFailed) {
            if (candidate.source == resolved.source) passedFailed = true;
            continue;
          }
          try {
            await _player.setAudioSource(await _audioSourceFor(candidate, track));
            fallback = candidate;
            loaded = true;
            break;
          } catch (_) { /* Continue in the configured order. */ }
        }
        if (!loaded || fallback == null) throw StateError('没有可用的已启用音源');
        _emitSourceNotice(fallback.source);
        if (!current()) return;
        mediaItem.add(_mediaItem(track));
        _activeLocalAudioPath =
            fallback.isLocalFile ? fallback.url.toFilePath() : null;
        if (autoplay) {
          await _startCurrentPlayback(track);
        }
      } catch (_) {
        try {
          final outer = Uri.parse(
              'https://music.163.com/song/media/outer/url?id=${track.id}.mp3');
          await _player.setAudioSource(AudioSource.uri(outer, headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36',
          }));
          if (!current()) return;
          mediaItem.add(_mediaItem(track));
          _activeLocalAudioPath = null;
          if (autoplay) {
            await _startCurrentPlayback(track);
          }
        } catch (_) {}
      }
    }
  }

  SongUrlData? _firstUrl(List<SongUrlData> urls) {
    for (final item in urls) {
      if (item.url != null && item.url!.isNotEmpty) return item;
      if (item.freeTrial) return item;
    }
    return null;
  }

  Future<void> playTrack(Track track) async {
    if (_index >= 0 &&
        (_index >= _tracks.length || _tracks[_index].id != track.id)) {
      _finishScrobble();
    }
    final existing = _tracks.indexWhere((e) => e.id == track.id);
    if (existing >= 0) {
      _index = existing;
    } else {
      final insertAt = _index < 0 ? 0 : _index + 1;
      _tracks.insert(insertAt.clamp(0, _tracks.length), track);
      _index = insertAt.clamp(0, _tracks.length - 1).toInt();
      queue.add(_tracks.map(_mediaItem).toList(growable: false));
    }
    _playNext.removeWhere((e) => e.id == track.id);
    mediaItem.add(_mediaItem(_tracks[_index]));
    _resetScrobbleForTrack(_tracks[_index], force: true);
    unawaited(_persistQueue());
    unawaited(_loadCurrent());
  }

  Future<void> playQueueItem(Track track) async {
    if (_index >= 0 &&
        (_index >= _tracks.length || _tracks[_index].id != track.id)) {
      _finishScrobble();
    }
    final mainIndex = _tracks.indexWhere((e) => e.id == track.id);
    if (mainIndex >= 0) {
      _index = mainIndex;
      mediaItem.add(_mediaItem(_tracks[_index]));
      unawaited(_persistQueue());
      unawaited(_loadCurrent());
      return;
    }
    if (_playNext.any((e) => e.id == track.id)) {
      final item = _playNext.firstWhere((e) => e.id == track.id);
      _playNext.remove(item);
      final insertAt = _index < 0 ? 0 : _index + 1;
      _tracks.insert(insertAt.clamp(0, _tracks.length), item);
      _index = insertAt.clamp(0, _tracks.length - 1).toInt();
      queue.add(_tracks.map(_mediaItem).toList(growable: false));
      mediaItem.add(_mediaItem(_tracks[_index]));
      unawaited(_persistQueue());
      unawaited(_loadCurrent());
    }
  }

  void insertAsNext(Track track) {
    _playNext.removeWhere((e) => e.id == track.id);
    _playNext.insert(0, track);
    unawaited(_persistQueue());
    unawaited(_preloadNext());
  }

  void removeFromUpcoming(Track track) {
    final nextIndex = _playNext.indexWhere((e) => e.id == track.id);
    if (nextIndex >= 0) {
      _playNext.removeAt(nextIndex);
      unawaited(_persistQueue());
      unawaited(_preloadNext());
      return;
    }
    final mainIndex = _tracks.indexWhere((e) => e.id == track.id);
    if (mainIndex > _index) {
      _tracks.removeAt(mainIndex);
      if (_tracks.isNotEmpty) {
        queue.add(_tracks.map(_mediaItem).toList(growable: false));
      }
    }
    unawaited(_persistQueue());
    unawaited(_preloadNext());
  }

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Track> get playNext => List.unmodifiable(_playNext);
  List<Track> get upcomingItems => List.unmodifiable([
        ..._playNext,
        if (_index + 1 < _tracks.length) ..._tracks.sublist(_index + 1),
      ]);
  int get currentIndex => _index;

  void setUpcomingOrder(List<Track> ordered) {
    final visible = upcomingItems;
    if (visible.length != ordered.length) return;
    final sourceIds = visible.map((e) => e.id).toList();
    final targetIds = ordered.map((e) => e.id).toList();
    if (sourceIds.toSet().length != targetIds.toSet().length ||
        !sourceIds.toSet().containsAll(targetIds)) {
      return;
    }
    final nextCount = _playNext.length;
    _playNext
      ..clear()
      ..addAll(ordered.take(nextCount));
    final prefix = _index >= 0 ? _tracks.take(_index + 1).toList() : <Track>[];
    _tracks
      ..clear()
      ..addAll(prefix)
      ..addAll(ordered.skip(nextCount));
    queue.add(_tracks.map(_mediaItem).toList(growable: false));
    unawaited(_persistQueue());
    unawaited(_preloadNext());
  }

  void reorderUpcomingItems(int oldIndex, int newIndex) {
    final visible = [...upcomingItems];
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    newIndex = newIndex.clamp(0, visible.length - 1).toInt();
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);
    final nextCount = _playNext.length;
    _playNext
      ..clear()
      ..addAll(visible.take(nextCount));
    final upcomingMain = visible.skip(nextCount).toList();
    final prefix = _index >= 0 ? _tracks.take(_index + 1).toList() : <Track>[];
    _tracks
      ..clear()
      ..addAll(prefix)
      ..addAll(upcomingMain);
    queue.add(_tracks.map(_mediaItem).toList(growable: false));
    unawaited(_persistQueue());
    unawaited(_preloadNext());
  }

  Future<void> setQuality(String value) async {
    if (quality == value) return;
    quality = value;
    _preloadGeneration++;
    _preloadedAudio.clear();
    _preloadFutures.clear();
    unawaited(_preloadNext());
  }

  Future<void> setUnblock(bool value) async {
    unblock = value;
  }

  @override
  Future<void> play() async {
    if (_player.audioSource == null) {
      await _loadCurrent();
    } else {
      if (_outgoing != null) unawaited(_outgoing!.play());
      unawaited(_player.play());
      unawaited(_preloadNext());
    }
  }

  @override
  Future<void> pause() async {
    ++_loadGeneration; // Invalidate an in-flight standby preparation.
    await _player.pause();
    await _outgoing?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    ++_loadGeneration;
    await _cancelCrossfade();
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    ++_loadGeneration;
    await _cancelCrossfade();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    _finishScrobble();
    if (_playNext.isNotEmpty) {
      final next = _playNext.removeAt(0);
      final insertAt = _index < 0 ? 0 : _index + 1;
      _tracks.insert(insertAt.clamp(0, _tracks.length), next);
      _index = insertAt.clamp(0, _tracks.length - 1).toInt();
      queue.add(_tracks.map(_mediaItem).toList(growable: false));
      mediaItem.add(_mediaItem(_tracks[_index]));
      unawaited(_persistQueue());
      unawaited(_loadCurrent());
      return;
    }

    if (_tracks.isEmpty) return;
    _index += 1;
    if (_index >= _tracks.length) {
      if (playbackState.value.repeatMode == AudioServiceRepeatMode.all) {
        _index = 0;
      } else {
        _index = _tracks.length - 1;
        unawaited(_persistQueue());
        await _player.pause();
        return;
      }
    }
    mediaItem.add(_mediaItem(_tracks[_index]));
    unawaited(_persistQueue());
    unawaited(_loadCurrent());
  }

  @override
  Future<void> skipToPrevious() async {
    _finishScrobble();
    if (_tracks.isEmpty) return;
    if (_player.position > const Duration(seconds: 4)) {
      await _player.seek(Duration.zero);
      return;
    }
    _index -= 1;
    if (_index < 0) {
      if (playbackState.value.repeatMode == AudioServiceRepeatMode.all) {
        _index = _tracks.length - 1;
      } else {
        _index = 0;
      }
    }
    mediaItem.add(_mediaItem(_tracks[_index]));
    unawaited(_persistQueue());
    unawaited(_loadCurrent());
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index != _index) _finishScrobble();
    if (index < 0 || index >= _tracks.length) return;
    _index = index;
    mediaItem.add(_mediaItem(_tracks[_index]));
    unawaited(_persistQueue());
    unawaited(_loadCurrent());
  }

  Future<void> playIndex(int index) async {
    if (index != _index) _finishScrobble();
    if (index < 0 || index >= _tracks.length) return;
    _index = index;
    mediaItem.add(_mediaItem(_tracks[_index]));
    unawaited(_persistQueue());
    unawaited(_loadCurrent());
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(
      repeatMode == AudioServiceRepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    unawaited(_preloadNext());
  }

  @override
  Future<void> onTaskRemoved() async {
    // Keep playback alive in the normal media-service flow; Android owns the
    // foreground service lifecycle. Explicit stop still terminates playback.
  }

  Future<void> disposeHandler() async {
    ++_loadGeneration;
    await _cancelCrossfade();
    await _position?.cancel();
    await _playerState?.cancel();
    await _player.dispose();
    await _sourceNoticeController.close();
  }
}
