import 'package:flutter/foundation.dart';
import '../api/netease_api.dart';
import '../api/netease_client.dart';
import '../models/models.dart';

class AccountStore extends ChangeNotifier {
  final api = NeteaseApi.instance;
  UserProfile? profile;
  Set<int> likedIds = {};
  List<PlaylistSummary> playlists = [];
  List<AlbumSummary> likedAlbums = [];
  List<ArtistSummary> likedArtists = [];
  bool loading = false;
  bool bootstrapped = false;
  String? lastError;

  bool get hasAuthCookie => NeteaseClient.instance.isLoggedIn;
  bool get isLoggedIn => profile != null && hasAuthCookie;
  int get vipType => profile?.vipType ?? 0;

  List<PlaylistSummary> get createdPlaylists {
    final p = profile;
    if (p == null) return const [];
    return playlists
        .where((v) => v.creator?.userId == p.userId && !v.isLikedSongsList)
        .toList();
  }

  List<PlaylistSummary> get subscribedPlaylists {
    final p = profile;
    if (p == null) return const [];
    return playlists.where((v) => v.creator?.userId != p.userId).toList();
  }

  PlaylistSummary? get likedPlaylist {
    for (final item in playlists) {
      if (item.isLikedSongsList) return item;
    }
    // Match the iOS fallback when the API omits the specialType/name marker.
    return playlists.isNotEmpty ? playlists.first : null;
  }

  /// Mirrors the iOS bootstrap contract:
  /// MUSIC_U cookie -> /weapi/w/nuser/account/get -> profile -> library.
  /// A valid cookie without a profile is deliberately not considered logged in.
  Future<bool> bootstrap({bool force = false}) async {
    if (bootstrapped && !loading && !force) return isLoggedIn;
    loading = true;
    lastError = null;
    notifyListeners();

    try {
      await NeteaseClient.instance.ensureReady();
      if (!NeteaseClient.instance.isLoggedIn) {
        profile = null;
        playlists = [];
        likedIds = {};
        return false;
      }

      // Refresh before reading account/library state so the first library
      // request does not race a just-restored session. Failure is harmless for
      // an otherwise valid MUSIC_U cookie.
      await api.refreshLogin();
      final fetched = await api.userAccount();
      if (fetched == null || fetched.userId <= 0) {
        lastError =
            '已获取登录 Cookie（MUSIC_U），但 /w/nuser/account/get 没有返回有效用户资料';
        profile = null;
        return false;
      }
      profile = fetched;

      // Library data is best-effort and must not invalidate the account itself.
      await refreshLibrary();

      // /w/nuser/account/get can return an incomplete profile. Always enrich
      // it from the authenticated /user/detail response so the avatar is not
      // dependent on which account response variant the server returned.
      if (profile != null) {
        try {
          final richer = await api.userDetail(profile!.userId);
          if (richer != null) {
            profile = profile!.copyWith(
              nickname: richer.nickname.isNotEmpty ? richer.nickname : profile!.nickname,
              avatarUrl: richer.avatarUrl ?? profile!.avatarUrl,
              backgroundUrl: richer.backgroundUrl ?? profile!.backgroundUrl,
              signature: richer.signature ?? profile!.signature,
              vipType: richer.vipType,
            );
          }
        } catch (_) {}
      }

      await _ensureLikedIdsFallback();
      return true;
    } catch (e) {
      lastError = '$e';
      profile = null;
      return false;
    } finally {
      bootstrapped = true;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    if (!isLoggedIn) return;
    final uid = profile!.userId;
    try {
      final values = await api.userPlaylists(uid);
      if (values.isNotEmpty || playlists.isEmpty) {
        playlists = values;
      }
    } catch (_) {}
    try {
      final ids = await api.likedTrackIds(uid);
      if (ids.isNotEmpty) {
        likedIds = ids;
      } else if (likedIds.isEmpty && likedPlaylist?.trackIds.isNotEmpty == true) {
        likedIds = likedPlaylist!.trackIds.toSet();
      }
    } catch (_) {
      if (likedIds.isEmpty && likedPlaylist?.trackIds.isNotEmpty == true) {
        likedIds = likedPlaylist!.trackIds.toSet();
      }
    }
    // iOS loads liked albums/artists as part of the authenticated library.
    // Keep these best-effort so a sublist endpoint failure never hides the rest
    // of the user's library.
    await refreshSublists();
    notifyListeners();
  }


  /// Immediately reflects a successful playlist subscribe/unsubscribe in the
  /// local authenticated library. The network list may lag briefly, so the UI
  /// must not depend on an immediate /user/playlist refresh.
  void applyPlaylistSubscription({
    required PlaylistSummary summary,
    required bool subscribed,
  }) {
    final index = playlists.indexWhere((item) => item.id == summary.id);
    if (subscribed) {
      final updated = PlaylistSummary(
        id: summary.id,
        name: summary.name,
        coverUrl: summary.coverUrl,
        playCount: summary.playCount,
        trackCount: summary.trackCount,
        copywriter: summary.copywriter,
        creator: summary.creator,
        specialType: summary.specialType,
        privacy: summary.privacy,
        subscribed: true,
        trackIds: summary.trackIds,
      );
      playlists = [...playlists];
      if (index >= 0) {
        playlists[index] = updated;
      } else {
        playlists.add(updated);
      }
    } else if (index >= 0) {
      playlists = [...playlists]..removeAt(index);
    }
    notifyListeners();
  }

  Future<void> _ensureLikedIdsFallback() async {
    if (!isLoggedIn) return;
    if (playlists.isEmpty && profile != null) {
      try {
        playlists = await api.userPlaylists(profile!.userId);
      } catch (_) {}
    }
    if (likedIds.isNotEmpty) {
      notifyListeners();
      return;
    }
    final liked = likedPlaylist;
    if (liked == null) return;
    if (liked.trackIds.isNotEmpty) {
      likedIds = liked.trackIds.toSet();
      notifyListeners();
      return;
    }
    try {
      final detail = await api.playlistDetail(liked.id);
      final ids = <int>{
        ...detail.playlist.trackIds,
        ...detail.playlist.tracks.map((track) => track.id),
      }..removeWhere((id) => id <= 0);
      if (ids.isNotEmpty) {
        likedIds = ids;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> ensureLibraryReady() async {
    if (!isLoggedIn) return false;
    await refreshLibrary();
    await _ensureLikedIdsFallback();
    return likedPlaylist != null && likedIds.isNotEmpty;
  }

  Future<void> reloadLikedLibrary() async {
    if (!isLoggedIn || profile == null) return;
    await refreshLibrary();
    if (likedPlaylist == null || likedIds.isEmpty) {
      await _ensureLikedIdsFallback();
    }
    notifyListeners();
  }

  /// Loads only the authenticated user's liked-song library.
  Future<List<Track>> likedTracks({int limit = 1000}) async {
    if (!isLoggedIn || profile == null) {
      throw const NeteaseException('请先登录');
    }

    // The iOS implementation opens 我喜欢的音乐 as the account's own playlist
    // and lets PlaylistDetailView load its trackIds + full song details. Do the
    // same first. This is more reliable than making /song/like/get the sole
    // source of truth because that endpoint can legitimately return no ids in
    // some account/session states even though the playlist is readable.
    await ensureLibraryReady();
    final playlist = likedPlaylist;
    if (playlist != null) {
      try {
        final detail = await api.playlistDetail(playlist.id);
        if (detail.playlist.tracks.isNotEmpty) {
          return detail.playlist.tracks.take(limit).toList(growable: false);
        }
        final all = await api.playlistTracksAll(playlist.id, limit: limit);
        if (all.isNotEmpty) return all.take(limit).toList(growable: false);
      } catch (_) {
        // Continue with the explicit like-id route below.
      }
    }

    // Compatibility fallback: exact iOS /song/like/get IDs + /v3/song/detail.
    if (likedIds.isEmpty) await _ensureLikedIdsFallback();
    final ids = likedIds.take(limit).toList(growable: false);
    if (ids.isNotEmpty) {
      final loaded = await api.songDetails(ids);
      if (loaded.isNotEmpty) return loaded;
    }

    throw const NeteaseException('你的喜欢歌曲暂时无法读取');
  }

  /// QR 803 may be accompanied by a cookie response that arrives just after
  /// the business response. Retry the iOS-style bootstrap briefly so the UI
  /// does not race the cookie jar.
  Future<bool> finishQrLogin({int attempts = 4}) async {
    await NeteaseClient.instance.ensureReady();
    for (var attempt = 0; attempt < attempts; attempt++) {
      final ok = await bootstrap(force: true);
      if (ok && isLoggedIn) return true;
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    return false;
  }

  bool liked(int id) => likedIds.contains(id);

  /// Kept only as a compatibility fallback for old callers. A profile is never
  /// accepted as authenticated when MUSIC_U was not captured.
  bool acceptLoginProfile(UserProfile value) {
    if (!NeteaseClient.instance.isLoggedIn || value.userId <= 0) {
      lastError = '扫码服务器返回了用户资料，但没有捕获有效 MUSIC_U Cookie';
      notifyListeners();
      return false;
    }
    profile = value;
    bootstrapped = true;
    lastError = null;
    notifyListeners();
    return true;
  }

  final Set<int> _pendingLikes = {};

  Future<void> toggleLike(int id) async {
    if (!isLoggedIn) throw const NeteaseException('请先登录');
    if (!_pendingLikes.add(id)) return;
    final next = !liked(id);
    if (next) {
      likedIds.add(id);
    } else {
      likedIds.remove(id);
    }
    notifyListeners();
    try {
      await api.likeTrack(id, next);
    } catch (e) {
      if (next) {
        likedIds.remove(id);
      } else {
        likedIds.add(id);
      }
      notifyListeners();
      rethrow;
    } finally {
      _pendingLikes.remove(id);
    }
  }

  Future<void> logout() async {
    await api.logout();
    profile = null;
    likedIds = {};
    playlists = [];
    likedAlbums = [];
    likedArtists = [];
    bootstrapped = true;
    lastError = null;
    notifyListeners();
  }

  Future<void> refreshSublists() async {
    if (!isLoggedIn) return;
    try {
      likedAlbums = await api.likedAlbums();
    } catch (_) {}
    try {
      likedArtists = await api.likedArtists();
    } catch (_) {}
    notifyListeners();
  }
}
