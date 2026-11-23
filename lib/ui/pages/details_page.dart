import '../widgets/cached_entry_snapshot.dart';
import '../widgets/content_fade.dart';
import '../widgets/loading_placeholder.dart';
import 'artist_catalog_page.dart';
import '../../core/storage/app_accent.dart';
import '../widgets/track_title.dart';
import '../widgets/glass_refresh.dart';
import '../widgets/glass_controls.dart';
import '../widgets/liquid_surface.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/netease_api.dart';
import '../../core/api/netease_client.dart';
import '../../core/models/models.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';
import '../widgets/common.dart';
import '../theme/app_theme.dart';

class PlaylistPage extends StatefulWidget {
  final int id;
  final String? initialCover;
  final bool ownedHeader;
  const PlaylistPage({super.key, required this.id, this.initialCover, this.ownedHeader = false});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage>
    {
  static final _recent = <String, ({PlaylistDetail detail, List<Track> tracks})>{};
  String get _cacheKey => '${context.read<AccountStore>().profile?.userId ?? 0}:${widget.id}';
  PlaylistDetail? detail;
  List<Track> tracks = [];
  bool loading = true;
  String? error;
  bool _animateSongs = true;
  bool _busySubscription = false;
  String _query = '';
  @override
  void initState() {
    super.initState();
    final cached = _recent.remove(_cacheKey);
    if (cached != null) {
      _animateSongs = false;
      _recent[_cacheKey] = cached;
      detail = cached.detail;
      tracks = List.of(cached.tracks);
      loading = false;
    } else { _load(); }
  }

  Future<void> _load() async {
    try {
      final result = await NeteaseApi.instance.playlistDetail(widget.id);
      if (!mounted) return;
      final account = context.read<AccountStore>();
      var playlist = result.playlist;
      // Some detail responses omit the current user's `subscribed` flag.
      // Prefer the authenticated library when it already contains this playlist.
      if (account.subscribedPlaylists.any((item) => item.id == playlist.id) &&
          !playlist.subscribed) {
        playlist = playlist.copyWith(subscribed: true);
      }
      if (playlist.cover == null || playlist.cover!.trim().isEmpty) {
        final carried = widget.initialCover?.trim();
        final resolved = carried != null && carried.isNotEmpty
            ? carried
            : await NeteaseApi.instance.playlistCover(widget.id);
        if (resolved != null && resolved.trim().isNotEmpty) {
          playlist = playlist.copyWith(cover: resolved);
        }
      }
      detail = playlist;
      tracks = playlist.tracks;

      // A user's liked playlist can legitimately return trackIds while the
      // public/detail response omits the expanded `tracks` payload. Hydrate
      // those IDs directly from the authenticated like cache so the page does
      // not appear empty even though the account has liked songs.
      final isLikedPlaylist = result.playlist.id == account.likedPlaylist?.id ||
          result.playlist.name.trim() == '我喜欢的音乐';
      if (tracks.isEmpty && isLikedPlaylist && account.likedIds.isNotEmpty) {
        final hydrated = await NeteaseApi.instance
            .songDetails(account.likedIds.take(1000).toList())
            .timeout(const Duration(seconds: 15));
        if (hydrated.isNotEmpty) {
          tracks = hydrated;
        }
      }
      if (!mounted) return;
      _recent.remove(_cacheKey);
      _recent[_cacheKey] = (detail: detail!, tracks: List.of(tracks));
      while (_recent.length > 1) { _recent.remove(_recent.keys.first); }
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      error = '$e';
      setState(() => loading = false);
    }
  }

  Future<void> _togglePlaylistSubscription(AccountStore account, PlaylistDetail playlist) async {
    if (!account.isLoggedIn) return;
    setState(() => _busySubscription = true);
    try {
      // The detail endpoint can occasionally omit `subscribed` even when the
      // same playlist is already present in the authenticated library. Prefer
      // the local library state when it has a concrete answer so we do not send
      // a duplicate subscribe request that the server may reject as too frequent.
      final inLibrary = account.subscribedPlaylists.any((item) => item.id == playlist.id);
      final currentlySubscribed = playlist.subscribed || inLibrary;
      final next = !currentlySubscribed;

      await NeteaseApi.instance.subscribePlaylist(playlist.id, next);

      if (!mounted) return;
      final updatedCount =
          (playlist.subscribedCount + (next ? 1 : -1)).clamp(0, 1 << 30);
      setState(() {
        detail = playlist.copyWith(
          subscribed: next,
          subscribedCount: updatedCount,
        );
      });

      // Update the visible library immediately. A successful subscribe can be
      // reflected by the server before /user/playlist catches up, so relying
      // only on a full refresh makes the new playlist appear missing.
      account.applyPlaylistSubscription(
        summary: PlaylistSummary(
          id: playlist.id,
          name: playlist.name,
          coverUrl: playlist.cover,
          playCount: playlist.playCount,
          trackCount: playlist.trackCount,
          creator: playlist.creator,
          subscribed: next,
          trackIds: playlist.trackIds,
        ),
        subscribed: next,
      );

      if (mounted) {
        context.read<PlayerController>().showNotice(next ? '已收藏歌单' : '已取消收藏歌单');
      }

      // The successful mutation is reflected immediately in AccountStore.
      // The next normal library refresh will reconcile with the server.

    } catch (e) {
      if (mounted) {
        context.read<PlayerController>().showNotice('$e');
      }
    } finally {
      if (mounted) setState(() => _busySubscription = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final account = context.watch<AccountStore>();
    final currentTrackId = context.select<PlayerController, int?>(
      (player) => player.currentTrack?.id);
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: KumoneGlassAppBar(title: const SizedBox.shrink()),
        body: Padding(padding: EdgeInsets.only(top: kumoneToolbarInset(context)),
          child: _PlaylistLoading(ownedHeader: widget.ownedHeader)),
      );
    }
    if (detail == null) {
      return Scaffold(
        appBar: KumoneGlassAppBar(title: const SizedBox.shrink()),
        body: _DetailError(message: error ?? '歌单数据为空', onRetry: _load),
      );
    }

    final playlist = detail!;
    final query = _query.trim().toLowerCase();
    final visibleTracks = query.isEmpty ? tracks : tracks.where((track) =>
        '${track.name} ${track.artistNames} ${track.album.name}'
            .toLowerCase().contains(query)).toList();
    final isUserLikedPlaylist = account.isLoggedIn &&
        (playlist.id == account.likedPlaylist?.id || playlist.name.trim() == '我喜欢的音乐');
    return CachedEntrySnapshot(identity: _cacheKey, family: 'playlist', ready: !loading, child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(
        title: const SizedBox.shrink(),
        actions: const [],
      ),
      body: KumoneGlassRefresh.adaptive(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: kumoneToolbarInset(context))),
            SliverToBoxAdapter(
              child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final coverSize = constraints.maxWidth < 400 ? 112.0 : 140.0;
                        final description = (playlist.description ?? '').trim();
                        final owned = account.isLoggedIn &&
                            playlist.creator?.userId == account.profile?.userId;
                        if (owned && !isUserLikedPlaylist) {
                          return Row(crossAxisAlignment: CrossAxisAlignment.center,
                            children: [Artwork(fadeIn: true, url: playlist.cover,
                              resolveUrl: () => NeteaseApi.instance.playlistCover(playlist.id),
                              size: 112, radius: 14, shadow: true),
                              const SizedBox(width: 18),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min, children: [
                                  KumoneLoadingText(playlist.name, style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 8),
                                  Text('${tracks.length} 首歌曲', style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 13)),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks),
                                    style: FilledButton.styleFrom(fixedSize: const Size.fromHeight(40),
                                      minimumSize: const Size(0, 40),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                    icon: const KumonePlayAllIcon(), label: const Text('播放全部')),
                                ])),
                            ]);
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Hero(
                                  tag: 'playlist-cover-${playlist.id}',
                                  child: Artwork(fadeIn: true, 
                                    url: playlist.cover,
                                    resolveUrl: () => NeteaseApi.instance.playlistCover(playlist.id),
                                    size: coverSize,
                                    radius: 14,
                                    shadow: true,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: _PlaylistHeaderInfo(playlist: playlist),
                                ),
                              ],
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              KumoneLoadingText(
                                description,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  height: 1.4,
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks),
                                    icon: const KumonePlayAllIcon(size: 22),
                                    label: const Text('播放全部'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      disabledBackgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .28),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(40),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(23),
                                      ),
                                      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                                if (!isUserLikedPlaylist && account.isLoggedIn && playlist.creator?.userId != account.profile?.userId) ...[
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: KumoneGlassIconButton(fadeIn: true, 
                                      tooltip: playlist.subscribed ? '取消收藏歌单' : '收藏歌单',
                                      onPressed: _busySubscription ? null : () => _togglePlaylistSubscription(account, playlist),
                                      style: IconButton.styleFrom(
                                        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: .72),
                                        foregroundColor: cs.onSurface,
                                        shape: const CircleBorder(),
                                      ),
                                      icon: _busySubscription
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Icon(playlist.subscribed ? Icons.check_rounded : Icons.add_rounded),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        );
                      },
                    ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: KumoneGlassSearchField(fadeIn: true, 
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索此歌单的歌曲、歌手或专辑',
                  ),
                ),
              ),
            ),
            if (tracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Row(
                    children: [
                      Text(
                        '${tracks.length} 首歌曲',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: visibleTracks.length,
              itemBuilder: (_, i) {
                final track = visibleTracks[i];
                final active = currentTrackId == track.id;
                return TrackActionMenu(
                  track: track,
                  showButton: false,
                  allowRemoveFromPlaylist: account.isLoggedIn &&
                      playlist.creator?.userId == account.profile?.userId &&
                      !isUserLikedPlaylist,
                  onRemoveFromPlaylist: () async {
                    await NeteaseApi.instance.playlistTracks('del', playlist.id, [track.id]);
                    if (!mounted) return;
                    setState(() {
                      tracks = tracks.where((e) => e.id != track.id).toList();
                    });
                  },
                  onOpenAlbum: (album) {
                    Navigator.of(context).push(kumonePageRoute(AlbumPage(id: album.id)));
                  },
                  onOpenArtist: (artist) {
                    Navigator.of(context).push(kumonePageRoute(ArtistPage(id: artist.id)));
                  },
                  child: HomeAppear(index: i, enabled: _animateSongs, child: Material(
                      color: active ? cs.primary.withValues(alpha: .065) : Colors.transparent,
                      child: InkWell(
                        onTap: () => player.playTracks(tracks, start: track),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 20, 8),
                          child: Row(
                            children: [
                              Artwork(fadeIn: true, 
                                url: track.album.picUrl,
                                size: 52,
                                radius: 9,
                                shadow: false,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    KumoneLoadingText(
                                      track.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                        color: active ? cs.primary : null,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (track.artistNames.isNotEmpty) track.artistNames,
                                        if (track.album.name.isNotEmpty) track.album.name,
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              KumoneLoadingText(
                                formatDuration(track.duration),
                                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
                );
              },
            ),
            if (visibleTracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _DetailError(
                  message: query.isEmpty ? '这个歌单没有返回可展示的歌曲' : '没有匹配的歌曲',
                ),
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24)),
          ],
        ),
      ),
    ));
  }
}

class _PlaylistHeaderInfo extends StatelessWidget {
  final PlaylistDetail playlist;

  const _PlaylistHeaderInfo({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final creator = playlist.creator;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KumoneLoadingText(
          playlist.name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
        ),
        if (creator != null && creator.nickname.isNotEmpty) ...[
          const SizedBox(height: 8),
          KumoneLoadingText(
            creator.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (playlist.playCount > 0) _MetaText('播放 ${formatCount(playlist.playCount)}'),
            if (playlist.subscribedCount > 0) _MetaText('${formatCount(playlist.subscribedCount)} 收藏'),
          ],
        ),
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  final String text;
  const _MetaText(this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: KumoneLoadingText(
        text,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _PlaylistLoading extends StatelessWidget {
  final bool ownedHeader;
  const _PlaylistLoading({this.ownedHeader = false});
  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height, {double? width, double radius = 8}) => Container(
      height: height, width: width,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(radius)));
    return LayoutBuilder(builder: (context, constraints) {
      final cover = ownedHeader || constraints.maxWidth - 48 < 400 ? 112.0 : 140.0;
      return ListView(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), children: [
        Row(children: [block(cover, width: cover, radius: 14),
          const SizedBox(width: 18), Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              block(20), const SizedBox(height: 8), block(14, width: 100),
              const SizedBox(height: 14),
              if (ownedHeader) block(40, width: 120, radius: 20)
              else block(13),
            ]))]),
        if (!ownedHeader) ...[
          const SizedBox(height: 16), block(14), const SizedBox(height: 6), block(14),
          const SizedBox(height: 18),
          Row(children: [Expanded(child: block(40, radius: 23)),
            const SizedBox(width: 10), block(40, width: 40, radius: 20)]),
        ],
        const SizedBox(height: 20), block(40, radius: 26), const SizedBox(height: 16),
        for (var i = 0; i < 8; i++) Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [block(52, width: 52, radius: 9),
            const SizedBox(width: 14), Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                block(15), const SizedBox(height: 7), block(12, width: 130)])),
            const SizedBox(width: 16), block(12, width: 30)])),
      ]);
    });
  }
}

class _DetailError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _DetailError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_off_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            KumoneLoadingText(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              KumoneLiquidSurface(
                  radius: 24,
                  child: TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新加载'),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class AlbumPage extends StatefulWidget {
  final int id;
  final int? sourceArtistId;
  const AlbumPage({super.key, required this.id, this.sourceArtistId});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  AlbumDetailResult? data;
  bool subscribed = false;
  bool subscriptionBusy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await NeteaseApi.instance.album(widget.id);
      if (loaded.album.id <= 0 && loaded.songs.isEmpty) {
        throw const NeteaseException('专辑数据为空');
      }
      data = loaded;
      subscribed = await NeteaseApi.instance.albumSubscribed(widget.id) ?? false;
      error = null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleSubscription() async {
    setState(() => subscriptionBusy = true);
    try {
      final next = !subscribed;
      await NeteaseApi.instance.subscribeAlbum(widget.id, next);
      if (!mounted) return;
      setState(() => subscribed = next);
      await context.read<AccountStore>().refreshSublists();
      if (mounted) {
        context.read<PlayerController>().showNotice(next ? '已收藏专辑' : '已取消收藏专辑');
      }
    } catch (e) {
      if (mounted) context.read<PlayerController>().showNotice('$e');
    } finally {
      if (mounted) setState(() => subscriptionBusy = false);
    }
  }

  ButtonStyle _playButtonStyle() => FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      );

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    if (data == null) {
      return Scaffold(
        appBar: const KumoneGlassAppBar(title: SizedBox.shrink()),
        body: Center(
          child: error == null ? const KumoneLoadingPlaceholder(header: true) : KumoneLoadingText(error!),
        ),
      );
    }

    final album = data!.album;
    final songs = data!.songs;
    final published = album.publishTime > 0
        ? DateTime.fromMillisecondsSinceEpoch(album.publishTime).toIso8601String().substring(0, 10)
        : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const KumoneGlassAppBar(title: SizedBox.shrink()),
      body: KumoneGlassRefresh.adaptive(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: kumoneToolbarInset(context))),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Artwork(fadeIn: true, url: album.picUrl, size: 112, radius: 14, shadow: true),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KumoneLoadingText(
                            album.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.08,
                                ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: album.artistId <= 0 || album.artistId == widget.sourceArtistId
                                ? null : () => Navigator.of(context).push(
                                    kumonePageRoute(ArtistPage(id: album.artistId))),
                            child: KumoneLoadingText(
                            album.artistName.isEmpty ? '未知歌手' : album.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          )),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (songs.isNotEmpty) '${songs.length} 首',
                              if (published != null) published,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: songs.isEmpty ? null : () => player.playTracks(songs),
                                  style: _playButtonStyle(),
                                  icon: const KumonePlayAllIcon(size: 22),
                                  label: const Text('播放全部'),
                                ),
                              ),
                              if (context.read<AccountStore>().isLoggedIn) ...[
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: KumoneGlassIconButton(fadeIn: true, 
                                    tooltip: subscribed ? '取消收藏专辑' : '收藏专辑',
                                    onPressed: subscriptionBusy ? null : _toggleSubscription,
                                    style: IconButton.styleFrom(
                                      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: .72),
                                      foregroundColor: cs.onSurface,
                                      shape: const CircleBorder(),
                                    ),
                                    icon: subscriptionBusy
                                        ? const SizedBox(
                                            width: 19,
                                            height: 19,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Icon(
                                            subscribed
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            color: subscribed ? AppAccent.appleRed.color : cs.onSurface,
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (_, i) {
                final track = songs[i];
                return TrackActionMenu(
                  track: track,
                  showButton: false,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Artwork(fadeIn: true, url: track.album.picUrl, size: 52, radius: 9),
                    title: KumoneTrackTitle(trackId: track.id, title: track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: KumoneLoadingText(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: KumoneLoadingText(
                      formatDuration(track.duration),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    onTap: () => player.playTracks(songs, start: track),
                  ),
                  onOpenAlbum: (ref) => Navigator.of(context).push(
                    kumonePageRoute(AlbumPage(id: ref.id)),
                  ),
                  onOpenArtist: (artist) => Navigator.of(context).push(
                    kumonePageRoute(ArtistPage(id: artist.id)),
                  ),
                );
              },
            ),
            SliverPadding(
              padding: EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24),
            ),
          ],
        ),
      ),
    );
  }
}

class ArtistPage extends StatefulWidget {
  final int id;
  const ArtistPage({super.key, required this.id});

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  ArtistDetailResult? data;
  bool followed = false;
  bool followBusy = false;
  List<AlbumSummary> albums = const [];
  List<Track> allSongs = const [];
  bool loadingExtras = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final base = await NeteaseApi.instance.artist(widget.id);
      final extras = await Future.wait([
        NeteaseApi.instance.artistTopSongs(widget.id),
        NeteaseApi.instance.artistAlbums(widget.id),
        NeteaseApi.instance.artistSongs(widget.id, limit: 100).catchError((_) => <Track>[]),
      ]);
      if (!mounted) return;
      final topSongs = extras[0] as List<Track>;
      final loadedAlbums = extras[1] as List<AlbumSummary>;
      final loadedSongs = extras[2] as List<Track>;
      final hot = topSongs.isNotEmpty ? topSongs : base.hotSongs;
      setState(() {
        data = ArtistDetailResult(base.artist, hot);
        followed = base.artist.followed;
        albums = loadedAlbums;
        allSongs = loadedSongs.isNotEmpty ? loadedSongs : hot;
        loadingExtras = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loadingExtras = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => followBusy = true);
    try {
      final next = !followed;
      await NeteaseApi.instance.subscribeArtist(widget.id, next);
      if (!mounted) return;
      setState(() => followed = next);
      await context.read<AccountStore>().refreshSublists();
      if (mounted) context.read<PlayerController>().showNotice(next ? '已关注歌手' : '已取消关注');
    } catch (e) {
      if (mounted) context.read<PlayerController>().showNotice('$e');
    } finally {
      if (mounted) setState(() => followBusy = false);
    }
  }

  ButtonStyle _playButtonStyle() => FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        minimumSize: const Size.fromHeight(40),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      );

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final cs = Theme.of(context).colorScheme;
    if (data == null) {
      return Scaffold(
        appBar: const KumoneGlassAppBar(title: SizedBox.shrink()),
        body: Center(
          child: error == null
              ? const _ArtistLoading()
              : _DetailError(message: error!, onRetry: _load),
        ),
      );
    }

    final artist = data!.artist;
    final hotSongs = data!.hotSongs;
    final songCount = artist.musicSize > 0 ? artist.musicSize : allSongs.length;
    final albumCount = artist.albumSize > 0 ? artist.albumSize : albums.length;
    final alias = artist.alias.where((value) => value.trim().isNotEmpty).join('、');

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(title: const SizedBox.shrink()),
      body: KumoneGlassRefresh.adaptive(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.only(
              top: kumoneToolbarInset(context),
              bottom: KumoneBottomOverlayInset.of(context) + 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Artwork(fadeIn: true, url: artist.picUrl, size: 112, radius: 56, circle: true, shadow: true),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KumoneLoadingText(
                          artist.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                        ),
                        if (alias.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '别名：$alias',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '$songCount 首歌曲 · $albumCount 张专辑',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: hotSongs.isEmpty ? null : () => player.playTracks(hotSongs),
                      style: _playButtonStyle(),
                      icon: const KumonePlayAllIcon(size: 22),
                      label: const Text('播放热门'),
                    ),
                  ),
                  if (context.read<AccountStore>().isLoggedIn) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: KumoneGlassIconButton(fadeIn: true, 
                        tooltip: followed ? '取消关注' : '关注歌手',
                        onPressed: followBusy ? null : _toggleFollow,
                        style: IconButton.styleFrom(
                          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: .72),
                          foregroundColor: cs.onSurface,
                          shape: const CircleBorder(),
                        ),
                        icon: followBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                followed
                                    ? Icons.check_rounded
                                    : Icons.person_add_alt_1_rounded,
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hotSongs.isNotEmpty) ...[
              SectionHeader(title: '热门歌曲', showChevron: true, onTap: () => Navigator.of(context).push(kumonePageRoute(ArtistCatalogPage(artistId: widget.id)))),
              ...hotSongs.take(20).map(
                (track) => TrackActionMenu(
                  track: track,
                  showButton: false,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Artwork(fadeIn: true, url: track.album.picUrl, size: 52, radius: 9),
                    title: KumoneTrackTitle(trackId: track.id, title: track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: KumoneLoadingText(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: KumoneLoadingText(
                      formatDuration(track.duration),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    onTap: () => player.playTracks(hotSongs, start: track),
                  ),
                  onOpenAlbum: (album) => Navigator.of(context).push(
                    kumonePageRoute(AlbumPage(id: album.id, sourceArtistId: widget.id)),
                  ),
                  onOpenArtist: (artist) => Navigator.of(context).push(
                    kumonePageRoute(ArtistPage(id: artist.id)),
                  ),
                ),
              ),
            ],
            if (albums.isNotEmpty) ...[
              SectionHeader(title: '专辑', showChevron: true, onTap: () => Navigator.of(context).push(kumonePageRoute(ArtistCatalogPage(artistId: widget.id, albums: true)))),
              SizedBox(
                height: 204,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: albums.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final album = albums[i];
                    return SizedBox(
                      width: 138,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).push(
                          kumonePageRoute(AlbumPage(id: album.id, sourceArtistId: widget.id)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Artwork(fadeIn: true, url: album.picUrl, size: 138, radius: 12),
                            const SizedBox(height: 7),
                            KumoneLoadingText(
                              album.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                            if (album.publishTime > 0)
                              KumoneLoadingText(
                                DateTime.fromMillisecondsSinceEpoch(album.publishTime).year.toString(),
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (loadingExtras && hotSongs.isEmpty && albums.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: SizedBox(height: 600, child: KumoneLoadingPlaceholder()),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtistLoading extends StatelessWidget {
  const _ArtistLoading();
  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget box(double h, {double? w, double radius = 8}) => Container(
      height: h, width: w, decoration: BoxDecoration(color: fill,
        borderRadius: BorderRadius.circular(radius)));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
      Row(children: [box(112, w: 112, radius: 56), const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          box(22), const SizedBox(height: 8), box(14),
          const SizedBox(height: 8), box(13, w: 110)]))]),
      const SizedBox(height: 14), Row(children: [Expanded(child: box(40, radius: 20)),
        const SizedBox(width: 10), box(40, w: 40, radius: 20)]),
      const SizedBox(height: 22), box(20, w: 100), const SizedBox(height: 12),
      for (var i = 0; i < 6; i++) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [box(52, w: 52, radius: 9), const SizedBox(width: 14),
          Expanded(child: Column(children: [box(16), const SizedBox(height: 8), box(12)]))])),
      const SizedBox(height: 20), box(20, w: 70), const SizedBox(height: 16),
      Row(children: [Expanded(child: AspectRatio(aspectRatio: 1, child: box(140, radius: 14))),
        const SizedBox(width: 14), Expanded(child: AspectRatio(aspectRatio: 1, child: box(140, radius: 14)))]),
    ]);
  }
}

class DailyPage extends StatefulWidget {
  const DailyPage({super.key});

  @override
  State<DailyPage> createState() => _DailyPageState();
}

class _DailyPageState extends State<DailyPage> {
  static final _dailyCache = <String, List<Track>>{};
  String get _dailyKey {
    final now = DateTime.now();
    return '${context.read<AccountStore>().profile?.userId ?? 0}:${now.year}-${now.month}-${now.day}';
  }
  List<Track> songs = const [];
  bool _animateSongs = true;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    final cached = _dailyCache[_dailyKey];
    if (cached != null) { _animateSongs = false; songs = List.of(cached); loading = false; }
    else { _load(); }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final daily = await NeteaseApi.instance.dailyRecommendSongs()
          .timeout(const Duration(seconds: 15));
      var value = daily;
      // A healthy public recommendation feed is preferable to an indefinite
      // spinner when a mirror returns an empty personalized daily feed.
      if (value.isEmpty) {
        value = await NeteaseApi.instance.personalizedNewsongs(limit: 30)
            .timeout(const Duration(seconds: 12));
      }
      if (!mounted) return;
      setState(() {
        if (value.isNotEmpty) {
          _dailyCache.clear();
          _dailyCache[_dailyKey] = List.of(value);
        }
        songs = value;
        loading = false;
        if (value.isEmpty) error = '暂时没有可用的每日推荐';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return CachedEntrySnapshot(identity: _dailyKey, family: 'daily', ready: !loading && songs.isNotEmpty, child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(title: const SizedBox.shrink()),
      body: loading
          ? Padding(padding: EdgeInsets.only(top: kumoneToolbarInset(context)),
              child: const KumoneLoadingPlaceholder())
          : songs.isEmpty
              ? _DetailError(message: error ?? '暂无每日推荐', onRetry: _load)
              : ListView.builder(
                  padding: EdgeInsets.only(top: kumoneToolbarInset(context), bottom: KumoneBottomOverlayInset.of(context) + 24),
                  itemCount: songs.length,
                  itemBuilder: (_, i) {
                    final track = songs[i];
                    return TrackActionMenu(
                      track: track,
                      showButton: false,
                      child: HomeAppear(index: i, enabled: _animateSongs, child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        leading: Artwork(fadeIn: true, url: track.album.picUrl, size: 52, radius: 9),
                        title: KumoneTrackTitle(trackId: track.id, title: track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: KumoneLoadingText(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: KumoneLoadingText(
                          formatDuration(track.duration),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        onTap: () => player.playTracks(songs, start: track),
                      )),
                      onOpenAlbum: (album) => Navigator.of(context).push(
                        kumonePageRoute(AlbumPage(id: album.id)),
                      ),
                      onOpenArtist: (artist) => Navigator.of(context).push(
                        kumonePageRoute(ArtistPage(id: artist.id)),
                      ),
                    );
                  },
                ),
    ));
  }
}
