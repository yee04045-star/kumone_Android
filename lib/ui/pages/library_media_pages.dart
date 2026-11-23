import '../widgets/content_fade.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/track_title.dart';
import '../widgets/glass_refresh.dart';
import '../widgets/liquid_surface.dart';
import '../widgets/glass_controls.dart';
import '../widgets/glass_category_chip.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/netease_api.dart';
import '../../core/models/models.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';
import '../widgets/common.dart';
import '../theme/app_theme.dart';
import 'details_page.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  bool week = false;
  bool loading = true;
  String? error;
  List<PlayRecordItem> records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = context.read<AccountStore>();
    if (!account.isLoggedIn || account.profile == null) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '请先登录';
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await NeteaseApi.instance
          .playRecords(account.profile!.userId, week: week)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        records = result;
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
    final tracks = records.map((e) => e.song).toList();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(title: const SizedBox.shrink()),
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    Expanded(child: GlassCategoryChip(menuOptics: true, label: '所有时间', selected: !week,
                      onTap: () { if (week) { setState(() => week = false); _load(); } })),
                    const SizedBox(width: 8),
                    Expanded(child: GlassCategoryChip(menuOptics: true, label: '最近一周', selected: week,
                      onTap: () { if (!week) { setState(() => week = true); _load(); } })),
                    const SizedBox(width: 8),
                    Expanded(child: SizedBox(height: 38, child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      onPressed: () { if (tracks.isNotEmpty) player.playTracks(tracks); },
                      child: const FittedBox(fit: BoxFit.scaleDown,
                        child: Text('播放全部', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)))))),
                  ]),
                ),
              ),
            ),
            if (loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: KumoneLoadingPlaceholder(),
              )
            else if (records.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _LibraryEmpty(
                  icon: Icons.history,
                  title: error ?? '暂无播放记录',
                  retry: _load,
                ),
              )
            else
              SliverList.builder(
                itemCount: records.length,
                itemBuilder: (_, i) {
                  final record = records[i];
                  return TrackActionMenu(
                    track: record.song,
                    showButton: false,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      leading: Artwork(fadeIn: true, url: record.song.album.picUrl, size: 52, radius: 9),
                      title: KumoneTrackTitle(trackId: record.song.id, title: record.song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${record.song.artistNames.isEmpty ? '未知歌手' : record.song.artistNames}${record.song.album.name.isEmpty ? '' : ' · ${record.song.album.name}'} · ${record.playCount} 次',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: KumoneLoadingText(
                        formatDuration(record.song.duration),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      onTap: () => player.playTracks(tracks, start: record.song),
                    ),
                    onOpenAlbum: (album) => Navigator.of(context).push(
                      kumonePageRoute(AlbumPage(id: album.id)),
                    ),
                    onOpenArtist: (artist) => Navigator.of(context).push(
                      kumonePageRoute(ArtistPage(id: artist.id)),
                    ),
                  );
                },
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24)),
          ],
        ),
      ),
    );
  }
}

class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  bool loading = true;
  String? error;
  CloudSongsResult result = const CloudSongsResult(items: []);
  String _query = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = context.read<AccountStore>();
    if (!account.isLoggedIn) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '请先登录';
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final generation = ++_loadGeneration;
      final value = await NeteaseApi.instance.allCloudSongs();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        result = value;
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
    final tracks = result.items.map((e) => e.simpleSong).whereType<Track>().toList();
    final query = _query.trim().toLowerCase();
    final visibleTracks = result.items.where((item) {
      final track = item.simpleSong;
      return track != null && (query.isEmpty ||
          '${track.name} ${track.artistNames} ${track.album.name} ${item.fileName ?? ''}'
              .toLowerCase().contains(query));
    }).map((item) => item.simpleSong!).toList();
    String? sizeInfo;
    if (result.size != null && result.maxSize != null && result.maxSize! > 0) {
      sizeInfo = '已使用 ${_gb(result.size!)} GB / ${_gb(result.maxSize!)} GB';
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const KumoneGlassAppBar(title: SizedBox.shrink()),
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: KumoneLiquidSurface(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sizeInfo ?? '已同步 ${tracks.length} 首云盘歌曲',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const KumonePlayAllIcon(),
                        label: const Text('播放全部'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: KumoneGlassSearchField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索歌曲、歌手、专辑或上传文件名',
                  ),
                ),
              ),
            ),
            if (loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: KumoneLoadingPlaceholder(),
              )
            else if (visibleTracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _LibraryEmpty(
                  icon: Icons.cloud_outlined,
                  title: error ?? (query.isEmpty ? '云盘还没有歌曲' : '没有匹配的歌曲'),
                  subtitle: error == null ? '在网易云音乐客户端上传的歌曲会出现在这里' : null,
                  retry: _load,
                ),
              )
            else
              SliverList.builder(
                itemCount: visibleTracks.length,
                itemBuilder: (_, i) {
                  final track = visibleTracks[i];
                  return TrackActionMenu(
                    track: track,
                    showButton: false,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      leading: Artwork(fadeIn: true, url: track.album.picUrl, size: 52, radius: 9),
                      title: KumoneTrackTitle(trackId: track.id, title: track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: KumoneLoadingText(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: KumoneLoadingText(
                        formatDuration(track.duration),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      onTap: () => player.playTracks(tracks, start: track),
                    ),
                    onOpenAlbum: (album) => Navigator.of(context).push(
                      kumonePageRoute(AlbumPage(id: album.id)),
                    ),
                    onOpenArtist: (artist) => Navigator.of(context).push(
                      kumonePageRoute(ArtistPage(id: artist.id)),
                    ),
                    onDeleteFromCloud: () async {
                      CloudSongItem? item;
                      for (final candidate in result.items) {
                        if (candidate.simpleSong?.id == track.id) {
                          item = candidate;
                          break;
                        }
                      }
                      if (item == null) return;
                      await NeteaseApi.instance.deleteCloudSong(item.songId);
                      if (!mounted) return;
                      setState(() {
                        result = CloudSongsResult(
                          items: result.items.where((e) => e.songId != item!.songId).toList(),
                          hasMore: result.hasMore,
                          size: result.size,
                          maxSize: result.maxSize,
                        );
                      });
                    },
                  );
                },
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24)),
          ],
        ),
      ),
    );
  }

  String _gb(int bytes) => (bytes / 1073741824).toStringAsFixed(1);
}

class _LibraryEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? retry;

  const _LibraryEmpty({required this.icon, required this.title, this.subtitle, this.retry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            KumoneLoadingText(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              KumoneLoadingText(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (retry != null) ...[
              const SizedBox(height: 16),
              KumoneLiquidSurface(
                  radius: 24,
                  interactive: false,
                  child: TextButton.icon(
                      onPressed: retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新加载'))),
            ],
          ],
        ),
      ),
    );
  }
}
