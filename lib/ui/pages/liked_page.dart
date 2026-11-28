import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../core/storage/settings_store.dart';
import '../widgets/cached_entry_snapshot.dart';
import '../widgets/content_fade.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/track_title.dart';
import '../widgets/glass_refresh.dart';
import '../widgets/glass_controls.dart';
import '../widgets/liquid_surface.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/api/netease_client.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';
import '../widgets/common.dart';
import '../theme/app_theme.dart';
import 'details_page.dart';

class LikedSongsPage extends StatefulWidget {
  const LikedSongsPage({super.key});

  @override
  State<LikedSongsPage> createState() => _LikedSongsPageState();
}

class _LikedSongsPageState extends State<LikedSongsPage> {
  static String? cachedKey;
  static List<Track>? cachedTracks;
  String get dataKey {
    final account = context.read<AccountStore>();
    final ids = account.likedIds.toList()..sort();
    return '${account.profile?.userId}:${account.likedRevision}:${ids.join(',')}';
  }
  bool _animateSongs = true;
  bool loading = true;
  String? error;
  List<Track> tracks = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (cachedKey == dataKey && cachedTracks != null) {
      tracks = List.of(cachedTracks!); loading = false; _animateSongs = false;
    } else { _load(); }
  }

  Future<void> _load() async {
    final account = context.read<AccountStore>();
    try {
      if (!account.isLoggedIn) throw const NeteaseException('请先登录');
      final loaded = await account
          .likedTracks(limit: 1000)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        cachedKey = dataKey; cachedTracks = List.of(loaded);
        tracks = loaded;
        loading = false;
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
    final cs = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final visible = tracks
        .where((track) =>
            query.isEmpty ||
            '${track.name} ${track.artistNames} ${track.album.name}'
                .toLowerCase()
                .contains(query))
        .toList();
    return CachedEntrySnapshot(identity: dataKey, family: 'liked', ready: !loading && error == null, child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(title: const SizedBox.shrink()),
      body: KumoneGlassRefresh.adaptive(
        onRefresh: _load,
        child: CustomScrollView(
          scrollCacheExtent: ScrollCacheExtent.pixels((context.watch<SettingsStore?>()?.listLazyLoading ?? true) ? 0 : 1000),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: kumoneToolbarInset(context))),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: loading ? Container(
                height: (dailyHeroHeight(MediaQuery.sizeOf(context)) - 40).clamp(160.0, 260.0),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)))
                : RecommendationHero(songs: tracks, liked: true,
                  onPlay: () { if (tracks.isNotEmpty) player.playTracks(tracks); }))),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: KumoneGlassSearchField(fadeIn: true, 
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: '搜索此歌单的歌曲、歌手或专辑'),
              ),
            )),
            if (loading)
              const SliverFillRemaining(
                  hasScrollBody: false,
                  child: KumoneLoadingPlaceholder())
            else if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _LikedEmpty(
                    message: error ?? (query.isEmpty ? '暂无喜欢的歌曲' : '没有匹配的歌曲'),
                    retry: _load),
              )
            else
              SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (_, i) {
                  final track = visible[i];
                  return TrackActionMenu(
                    track: track,
                    showButton: false,
                    child: HomeAppear(index: i, enabled: _animateSongs, child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 2),
                      leading: Artwork(fadeIn: true, 
                          url: track.album.picUrl,
                          size: 48,
                          radius: 8,
                          shadow: false),
                      title: KumoneTrackTitle(trackId: track.id, title: track.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        track.artistNames.isEmpty ? '未知歌手' : track.artistNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: KumoneTrackTrailing(album: track.album.name, duration: KumoneLoadingText(formatDuration(track.duration), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
                      onTap: () => player.playTracks(tracks, start: track),
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
            SliverPadding(
                padding: EdgeInsets.only(
                    bottom: KumoneBottomOverlayInset.of(context) + 24)),
          ],
        ),
      ),
    ));
  }
}

class _LikedEmpty extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const _LikedEmpty({required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_border_rounded, size: 42),
          const SizedBox(height: 10),
          KumoneLoadingText(message),
          const SizedBox(height: 12),
          KumoneLiquidSurface(
              radius: 24,
              child: TextButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'))),
        ],
      );
}
