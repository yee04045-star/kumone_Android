import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/artwork_url.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:audio_service/audio_service.dart';
import '../models/models.dart';
import 'audio_handler.dart';
import '../models/lyrics.dart';
import '../api/netease_api.dart';

class PlayerController extends ChangeNotifier {
  final KumoneAudioHandler handler;

  List<Track> queue = [];
  List<Track> playNext = [];
  int currentIndex = -1;
  Track? currentTrack;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool shuffle = false;
  AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none;
  String quality = 'exhigh';
  bool unblock = true;

  double get volume => handler.volume;

  set volume(double value) {
    final safe = value.clamp(0.0, 1.0).toDouble();
    unawaited(handler.setVolume(safe));
    notifyListeners();
  }
  List<Track> _preShuffleUpcoming = const [];

  StreamSubscription? _state;
  StreamSubscription? _item;
  StreamSubscription? _sourceNoticeSub;
  Timer? _ticker;
  Timer? _noticeTimer;
  String? sourceNotice;
  final Map<int, ParsedLyrics?> _lyricsCache = {};
  final Map<int, Future<ParsedLyrics?>> _lyricsInflight = {};

  PlayerController(this.handler) {
    _syncFromHandler();
    _state = handler.playbackState.listen((state) {
      isPlaying = state.playing;
      position = state.updatePosition;
      duration = currentTrack?.duration ?? Duration.zero;
      _syncFromHandler(notify: false);
      notifyListeners();
    });
    _item = handler.mediaItem.listen((_) {
      _syncFromHandler();
      final track = currentTrack;
      if (track != null) unawaited(lyrics(track));
    });
    _sourceNoticeSub = handler.sourceNotices.listen(showNotice);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      position = handler.playbackState.value.updatePosition;
      _syncFromHandler(notify: false);
      notifyListeners();
    });
  }

  void showNotice(String message) {
    _noticeTimer?.cancel();
    sourceNotice = message;
    notifyListeners();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      sourceNotice = null;
      notifyListeners();
    });
  }

  String? _requestedClearCover;
  void _warmCurrentCover() {
    final raw = currentTrack?.album.picUrl;
    if (raw == null || raw.isEmpty) return;
    final url = artworkUrl(raw, thumbnail: false);
    final uri = Uri.tryParse(url);
    if (uri == null || !const ['http', 'https'].contains(uri.scheme) ||
        url == _requestedClearCover) { return; }
    _requestedClearCover = url;
    unawaited(DefaultCacheManager().getSingleFile(url).then<void>((_) {},
      onError: (Object error, StackTrace stack) {
        if (_requestedClearCover == url) _requestedClearCover = null;
      }));
  }

  void _syncFromHandler({bool notify = true}) {
    queue = handler.tracks;
    playNext = handler.playNext;
    currentIndex = handler.currentIndex;
    currentTrack = currentIndex >= 0 && currentIndex < queue.length
        ? queue[currentIndex]
        : null;
    duration = currentTrack?.duration ?? Duration.zero;
    _warmCurrentCover();
    if (notify) notifyListeners();
  }

  Future<void> playTracks(List<Track> tracks, {int index = 0, Track? start}) async {
    if (tracks.isEmpty) return;
    var selected = index.clamp(0, tracks.length - 1).toInt();
    if (start != null) {
      final found = tracks.indexWhere((e) => e.id == start.id);
      if (found >= 0) selected = found;
    }
    await handler.setTracks(tracks, index: selected, autoplay: true);
    _syncFromHandler();
  }

  Future<void> playTrack(Track track) async {
    await handler.playTrack(track);
    _syncFromHandler();
  }

  Future<void> playQueueItem(Track track) async {
    await handler.playQueueItem(track);
    _syncFromHandler();
  }

  Future<void> toggle() async {
    if (isPlaying) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> next() async => handler.skipToNext();
  Future<void> previous() async => handler.skipToPrevious();
  Future<void> seek(Duration target) async {
    var safe = target < Duration.zero ? Duration.zero : target;
    if (duration > Duration.zero && safe > duration) safe = duration;
    position = safe;
    notifyListeners();
    await handler.seek(safe);
    position = handler.playbackState.value.updatePosition;
    notifyListeners();
  }

  void insertAsNext(Track track) {
    handler.insertAsNext(track);
    _syncFromHandler();
  }

  void removeFromQueue(Track track) {
    handler.removeFromUpcoming(track);
    _syncFromHandler();
  }

  void reorderUpcoming(int oldIndex, int newIndex) {
    handler.reorderUpcomingItems(oldIndex, newIndex);
    _syncFromHandler();
  }

  Future<void> setQuality(String value) async {
    quality = value;
    await handler.setQuality(value);
    notifyListeners();
  }

  Future<void> setUnblock(bool value) async {
    unblock = value;
    await handler.setUnblock(value);
    notifyListeners();
  }

  Future<void> setRepeat(AudioServiceRepeatMode mode) async {
    repeatMode = mode;
    await handler.setRepeatMode(mode);
    notifyListeners();
  }

  void toggleShuffle() {
    final upcoming = [...handler.upcomingItems];
    if (!shuffle) {
      if (upcoming.length > 1) {
        _preShuffleUpcoming = List<Track>.from(upcoming);
        upcoming.shuffle();
        handler.setUpcomingOrder(upcoming);
        _syncFromHandler(notify: false);
      }
      shuffle = true;
    } else {
      final savedIds = _preShuffleUpcoming.map((e) => e.id).toList();
      final currentIds = upcoming.map((e) => e.id).toList();
      if (savedIds.length == currentIds.length &&
          savedIds.toSet().length == currentIds.toSet().length &&
          savedIds.toSet().containsAll(currentIds)) {
        handler.setUpcomingOrder(_preShuffleUpcoming);
        _syncFromHandler(notify: false);
      }
      _preShuffleUpcoming = const [];
      shuffle = false;
    }
    notifyListeners();
  }

  String get playbackModeLabel {
    if (shuffle) return '随机播放';
    if (repeatMode == AudioServiceRepeatMode.one) return '单曲循环';
    if (repeatMode == AudioServiceRepeatMode.all) return '列表循环';
    return '顺序播放';
  }

  Future<void> cyclePlaybackMode() async {
    // The player exposes the same three-state interaction as the lyrics/cover
    // toggle: normal state is unselected, then single-repeat, then shuffle.
    // 列表顺序播放 → 单曲循环 → 随机播放 → 列表顺序播放。
    if (shuffle) {
      toggleShuffle();
      await setRepeat(AudioServiceRepeatMode.none);
      return;
    }

    if (repeatMode == AudioServiceRepeatMode.one) {
      await setRepeat(AudioServiceRepeatMode.none);
      toggleShuffle();
      return;
    }

    // Treat a legacy/external list-loop state as normal order before entering
    // the first visible selectable mode. The UI no longer exposes list-loop.
    if (repeatMode == AudioServiceRepeatMode.all) {
      await setRepeat(AudioServiceRepeatMode.one);
      return;
    }

    await setRepeat(AudioServiceRepeatMode.one);
  }

  IconData get playbackModeIcon {
    if (shuffle) return CupertinoIcons.shuffle;
    if (repeatMode == AudioServiceRepeatMode.one) {
      return CupertinoIcons.repeat_1;
    }
    // Default, unselected state: list-order playback. This is deliberately
    // not a highlighted/selected repeat symbol.
    return CupertinoIcons.repeat;
  }

  void invalidateLyrics(int trackId) {
    _lyricsCache.remove(trackId);
  }

  Future<ParsedLyrics?> lyrics(Track track) {
    final cached = _lyricsCache[track.id];
    if (_lyricsCache.containsKey(track.id)) return Future.value(cached);
    final existing = _lyricsInflight[track.id];
    if (existing != null) return existing;
    final future = () async {
      try {
        final r = await NeteaseApi.instance.lyric(track.id);
        final parsed = LyricsParser.parse(
          r.lrc,
          tlyric: r.tlyric,
          ytlrc: r.ytlrc,
          romalrc: r.romalrc,
          yromalrc: r.yromalrc,
          yrc: r.yrc,
        );
        final enriched = await LyricsParser.enrichJapanese(parsed);
        _lyricsCache[track.id] = enriched;
        return enriched;
      } catch (_) {
        _lyricsCache.remove(track.id);
        return null;
      } finally {
        _lyricsInflight.remove(track.id);
      }
    }();
    _lyricsInflight[track.id] = future;
    return future;
  }

  @override
  void dispose() {
    _state?.cancel();
    _item?.cancel();
    _ticker?.cancel();
    _sourceNoticeSub?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }
}
