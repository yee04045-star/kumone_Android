import 'app_shell.dart';
import '../widgets/glass_refresh.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../core/api/netease_api.dart';
import '../../core/api/netease_client.dart';
import '../../core/models/models.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';
import '../widgets/common.dart';
import '../theme/app_theme.dart';
import 'details_page.dart';

class _RadarPlaylist {
  final int id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  const _RadarPlaylist({
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _radarIds = <int>[
    3136952023,
    2829883282,
    2829816518,
    2829896389,
  ];

  final api = NeteaseApi.instance;
  List<PlaylistSummary> playlists = [];
  List<_RadarPlaylist> radarPlaylists = [];
  List<ToplistItem> charts = [];
  List<AlbumSummary> albums = [];
  List<ArtistSummary> artists = [];
  String? dailyCover;
  bool loading = true;
  bool? _loadedForLogin;
  int _generation = 0;

  Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  Future<List<PlaylistSummary>> _loadPlaylists(bool loggedIn) async {
    // iOS: anonymous users still receive personalized/public playlist data.
    // Only /v1/discovery/recommend/resource is login-specific.
    final recommend = loggedIn
        ? await _safe(api.recommendResource())
        : const <PlaylistSummary>[];
    final personalized = await _safe(api.personalizedPlaylists(limit: 30));
    final combined = <PlaylistSummary>[
      ...(recommend ?? const <PlaylistSummary>[]),
      ...(personalized ?? const <PlaylistSummary>[]),
    ];
    final seen = <int>{};
    return combined.where((p) => p.id > 0 && seen.add(p.id)).toList();
  }

  Future<_RadarPlaylist?> _loadRadarOne(int id) async {
    final responses = await Future.wait<dynamic>([
      _safe(api.playlistBrief(id)),
      _safe(api.playlistDetail(id)),
    ]);
    final brief = responses[0] as PlaylistSummary?;
    final detail = responses[1] as PlaylistDetailResult?;

    var name = brief?.name ?? '';

    // iOS's Radar shelf is backed by the personalized radar playlist data.
    // For these generated playlists the visible Radar card uses the artwork
    // of its first song's album, rather than repeating the generic playlist
    // cover shown by the Recommendation shelf. Prefer that exact visual cue.
    String? cover = detail?.playlist.tracks.firstOrNull?.album.picUrl;
    if (detail != null) {
      final playlist = detail.playlist;
      if (playlist.name.isNotEmpty) name = playlist.name;
    }

    // Some playlist-detail variants return only metadata / trackIds. Fetch the
    // first song explicitly so the Radar shelf can still use its album art.
    if (cover == null || cover.isEmpty) {
      final tracks = await _safe(api.playlistTracksAll(id, limit: 1));
      cover = tracks?.firstOrNull?.album.picUrl;
    }

    // Only fall back to the playlist artwork after first-track artwork was
    // exhausted. This keeps ordinary playlist covers as a safety net without
    // reintroducing the duplicate Radar/Recommended image.
    cover ??= detail?.playlist.cover ?? brief?.coverUrl;
    if (cover == null || cover.isEmpty) {
      try {
        cover = await api.playlistCover(id);
      } catch (_) {}
    }

    if (name.isEmpty && (cover == null || cover.isEmpty)) return null;
    final parts = name.split('|');
    final title = parts.length > 1 ? parts.last.trim() : name.trim();
    final subtitle = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('|').trim()
        : null;
    return _RadarPlaylist(
      id: id,
      title: title.isEmpty ? '雷达歌单' : title,
      subtitle: subtitle?.isEmpty == true ? null : subtitle,
      coverUrl: cover,
    );
  }

  Future<List<_RadarPlaylist>> _loadRadar() async {
    final values = await Future.wait(
      _radarIds.map(_loadRadarOne),
    );
    return values.whereType<_RadarPlaylist>().toList(growable: false);
  }

  Future<void> _load({bool? loggedIn}) async {
    final account = loggedIn ?? context.read<AccountStore>().isLoggedIn;
    final generation = ++_generation;
    if (mounted) setState(() => loading = true);

    final playlistFuture = _loadPlaylists(account);
    final chartsFuture = _safe(api.toplists());
    final albumsFuture = _safe(api.newAlbums());
    final artistsFuture = _safe(api.topArtists());
    final dailyFuture = account ? _safe(api.dailyRecommendSongs()) : null;
    final radarFuture = account ? _loadRadar() : null;

    final loadedPlaylists = await playlistFuture;
    final loadedCharts = await chartsFuture;
    final loadedAlbums = await albumsFuture;
    final loadedArtists = await artistsFuture;
    final loadedDaily = dailyFuture == null ? null : await dailyFuture;
    final loadedRadar = radarFuture == null
        ? const <_RadarPlaylist>[]
        : await radarFuture;

    if (!mounted || generation != _generation) return;
    setState(() {
      playlists = loadedPlaylists;
      charts = (loadedCharts ?? []).where((item) {
        const ids = {19723756, 3779629, 2884035, 3778678, 60198};
        return ids.contains(item.id);
      }).toList();
      albums = (loadedAlbums ?? []).take(20).toList();
      artists = (loadedArtists ?? []).toList();
      dailyCover = loadedDaily?.firstOrNull?.album.picUrl;
      radarPlaylists = loadedRadar;
      loading = false;
    });
  }

  Future<void> _playFm(PlayerController player) async {
    try {
      final tracks = await api.personalFm();
      if (tracks.isEmpty) {
        throw const NeteaseException('私人漫游暂时没有可播放歌曲');
      }
      await player.playTracks(tracks);
    } catch (e) {
      if (!mounted) return;
      _showMessage('私人漫游启动失败：$e');
    }
  }

  Future<void> _playHeartbeat(
    AccountStore account,
    PlayerController player,
  ) async {
    // Match the iOS HomeView exactly: the account bootstrap supplies both
    // the special "我喜欢的音乐" playlist and the liked-track ID set. Do not
    // rebuild the seed pool from playlist details and do not fire a burst of
    // intelligence requests; one fresh random liked song is the iOS contract.
    var likedPlaylist = account.likedPlaylist;
    var likedIds = account.likedIds;
    if (likedPlaylist == null || likedIds.isEmpty) {
      await account.ensureLibraryReady();
      likedPlaylist = account.likedPlaylist;
      likedIds = account.likedIds;
    }

    if (likedPlaylist == null || likedIds.isEmpty) {
      if (!mounted) return;
      _showMessage('先收藏一些喜欢的歌曲，再使用心动模式');
      return;
    }

    final ids = likedIds.toList(growable: false);
    final seed = ids[Random().nextInt(ids.length)];

    try {
      // Exact iOS request: songId + type=fromPlayOne + playlistId +
      // startMusicId + count=1.
      final tracks = await api.intelligenceList(seed, likedPlaylist.id);
      if (tracks.isEmpty) {
        _showMessage('心动模式暂时不可用');
        return;
      }
      await player.playTracks(tracks);
    } catch (e) {
      if (!mounted) return;
      _showMessage('心动模式启动失败：$e');
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 144),
        shape: const StadiumBorder(),
        elevation: 0,
        backgroundColor: Colors.black.withValues(alpha: .78),
      ),
    );
  }

  void _openPlaylist(int id, {String? cover}) {
    Navigator.of(context).push(
      kumonePageRoute(PlaylistPage(id: id, initialCover: cover)),
    );
  }

  void _openAlbum(int id) {
    Navigator.of(context).push(kumonePageRoute(AlbumPage(id: id)));
  }

  void _openArtist(int id) {
    Navigator.of(context).push(kumonePageRoute(ArtistPage(id: id)));
  }

  Widget _homeSectionHeader(String title, bool showChevron) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -.25,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Text(title, style: titleStyle),
          const Spacer(),
          if (showChevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  Widget _shelf(
    String title,
    List<Widget> children, {
    required double height,
    bool chevron = false,
  }) {
    if (children.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _homeSectionHeader(title, chevron),
            SizedBox(
              height: height,
              child: ListView.separated(
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: children.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, index) => HomeAppear(
                  index: index,
                  child: children[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountStore>();
    final player = context.read<PlayerController>();

    if (_loadedForLogin != account.isLoggedIn) {
      _loadedForLogin = account.isLoggedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(loggedIn: _loadedForLogin);
      });
    }

    final slivers = <Widget>[
      KumoneScrollingTabHeader(
        title: const Text('推荐'),
        actions: [if (account.isLoggedIn) Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => AppShell.selectTab(context, 3),
            child: Artwork(url: account.profile?.avatarUrl, size: 36,
              circle: true, radius: 18, shadow: false)))],
      ),
    ];

    if (loading) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          sliver: SliverList.list(
            children: [
              _skeletonRow(width: 230, height: 132),
              const SizedBox(height: 30),
              _skeletonRow(width: 160, height: 204),
              const SizedBox(height: 30),
              _skeletonRow(width: 160, height: 204),
            ],
          ),
        ),
      );
    } else {
      // iOS hides the personalized feature shelf for anonymous visitors.
      if (account.isLoggedIn) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 34),
              child: SizedBox(
                height: 142,
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: 3,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (_, i) {
                    final Widget card = switch (i) {
                      0 => FeatureCard(
                          title: '每日推荐',
                          subtitle: '根据你的口味生成',
                          icon: CupertinoIcons.calendar,
                          colors: const [
                            Color(0xFF9F5C4D),
                            Color(0xFF4D3B31),
                          ],
                          imageUrl: dailyCover,
                          showsDate: true,
                          onTap: () => Navigator.of(context).push(
                            kumonePageRoute(const DailyPage()),
                          ),
                        ),
                      1 => FeatureCard(
                          title: '私人漫游',
                          subtitle: '从喜欢的歌开始漫游',
                          icon: CupertinoIcons.waveform,
                          colors: const [
                            Color(0xFF29325F),
                            Color(0xFF5D4095),
                          ],
                          onTap: () => _playFm(player),
                        ),
                      _ => FeatureCard(
                          title: '心动模式',
                          subtitle: '你的红心歌曲和相似推荐',
                          icon: CupertinoIcons.heart_fill,
                          colors: const [
                            Color(0xFFD93259),
                            Color(0xFFF76B55),
                          ],
                          onTap: () => _playHeartbeat(account, player),
                        ),
                    };
                    return HomeAppear(index: i, child: card);
                  },
                ),
              ),
            ),
          ),
        );
      }

      slivers.add(
        _shelf(
          '推荐歌单',
          playlists.take(12).map((p) {
            return PlaylistCard(
              item: p,
              onTap: () => _openPlaylist(p.id, cover: p.coverUrl),
              width: 160,
              resolveArtwork: () => NeteaseApi.instance.playlistCover(p.id),
            );
          }).toList(),
          height: 226,
        ),
      );

      if (radarPlaylists.isNotEmpty) {
        slivers.add(
          _shelf(
            '雷达歌单',
            radarPlaylists.map((r) {
              final summary = PlaylistSummary(
                id: r.id,
                name: r.title,
                coverUrl: r.coverUrl,
                copywriter: r.subtitle,
              );
              return PlaylistCard(
                item: summary,
                onTap: () => _openPlaylist(r.id, cover: r.coverUrl),
                width: 160,
                resolveArtwork: () => NeteaseApi.instance.playlistCover(r.id),
              );
            }).toList(),
            height: 226,
          ),
        );
      }

      slivers.add(
        _shelf(
          '排行榜',
          charts.map((chart) {
            return _ChartCard(
              item: chart,
              onTap: () => _openPlaylist(chart.id),
            );
          }).toList(),
          height: 226,
        ),
      );

      slivers.add(
        _shelf(
          '新碟上架',
          albums.map((album) {
            return _AlbumCard(
              item: album,
              onTap: () => _openAlbum(album.id),
            );
          }).toList(),
          height: 226,
        ),
      );

      slivers.add(
        _shelf(
          '推荐歌手',
          artists.take(12).map((artist) {
            return _ArtistCard(
              item: artist,
              onTap: () => _openArtist(artist.id),
            );
          }).toList(),
          height: 196,
        ),
      );

      if (playlists.isEmpty && charts.isEmpty && albums.isEmpty && artists.isEmpty) {
        slivers.add(
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('暂时没有加载到推荐内容，请下拉刷新')),
          ),
        );
      }

      slivers.add(
        SliverPadding(padding: EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24)),
      );
    }

    return KumoneGlassRefresh.adaptive(
      onRefresh: () => _load(loggedIn: account.isLoggedIn),
      edgeOffset: 12,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: slivers,
      ),
    );
  }

  Widget _skeletonRow({required double width, required double height}) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .72),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final ToplistItem item;
  final VoidCallback onTap;
  const _ChartCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return KumoneInteractive(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'playlist-cover-${item.id}',
              child: Artwork(
                url: item.coverImgUrl,
                size: 160,
                radius: 9,
                shadow: false,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            if (item.updateFrequency != null)
              Text(
                item.updateFrequency!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final AlbumSummary item;
  final VoidCallback onTap;
  const _AlbumCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return KumoneInteractive(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'album-cover-${item.id}',
              child: Artwork(
                url: item.picUrl,
                resolveUrl: () => NeteaseApi.instance.albumCover(item.id),
                size: 160,
                radius: 9,
                shadow: false,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            if (item.artistName.isNotEmpty)
              Text(
                item.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final ArtistSummary item;
  final VoidCallback onTap;
  const _ArtistCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return KumoneInteractive(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 140,
        child: Column(
          children: [
            Hero(
              tag: 'artist-cover-${item.id}',
              child: Artwork(
                url: item.picUrl,
                resolveUrl: () => NeteaseApi.instance.artistCover(item.id),
                size: 128,
                radius: 64,
                circle: true,
                shadow: false,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
