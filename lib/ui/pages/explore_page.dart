import '../widgets/content_fade.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/glass_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/api/netease_api.dart';
import '../../core/models/models.dart';
import '../widgets/common.dart';
import '../widgets/glass_category_chip.dart';
import 'details_page.dart';
import '../theme/app_theme.dart';

/// The iOS reference treats 精选 as a playlist catalogue.  The only special
/// branch is the explicit “排行榜” category; the default “全部” branch must
/// never fall back to chart IDs just because a playlist request failed.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  static const categories = <String>[
    '全部',
    '推荐歌单',
    '精品歌单',
    '排行榜',
    '官方',
    '华语',
    '流行',
    '摇滚',
    '民谣',
    '电子',
    '轻音乐',
    '说唱',
    '爵士',
    '古典',
    '影视原声',
    'ACG',
    '古风',
    '怀旧',
    '治愈',
    '放松',
    '伤感',
    '快乐',
    '学习',
    '工作',
    '运动',
    '驾车',
    '夜晚',
  ];

  final _categoryCache = <String, ({List<PlaylistSummary> playlists,
    List<ToplistItem> toplists, int offset, int before, bool more, String? error})>{};
  void _saveCategory() {
    if (loading) return;
    _categoryCache[category] = (playlists: List.of(playlists), toplists: List.of(toplists),
      offset: offset, before: highQualityBefore, more: hasMore, error: error);
  }
  String category = '全部';
  List<PlaylistSummary> playlists = [];
  List<ToplistItem> toplists = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  int offset = 0;
  int highQualityBefore = 0;
  String? error;
  int _requestToken = 0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _load(reset: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || loading || loadingMore || !hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter < 700) {
      unawaited(_load(reset: false));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _showToplists => category == '排行榜';

  Future<void> _load({required bool reset}) async {
    final token = ++_requestToken;
    if (reset) {
      if (mounted) {
        setState(() {
          playlists = [];
          toplists = [];
          offset = 0;
          highQualityBefore = 0;
          hasMore = true;
          loading = true;
          error = null;
        });
      }
    } else {
      if (loadingMore || !hasMore) return;
      if (mounted) setState(() => loadingMore = true);
    }

    try {
      await NeteaseApi.instance.ensureGuestSession();

      if (_showToplists) {
        final result = await NeteaseApi.instance.toplists();
        if (!mounted || token != _requestToken) return;
        setState(() {
          toplists = result;
          hasMore = false;
          error = result.isEmpty ? '排行榜暂时没有数据，请稍后重试' : null;
        });
        return;
      }

      List<PlaylistSummary> incoming = [];
      var nextHasMore = false;
      var nextOffset = offset;
      var nextHighQualityBefore = highQualityBefore;

      if (category == '推荐歌单') {
        incoming = await NeteaseApi.instance.personalizedPlaylists(limit: 100);
        nextHasMore = false;
      } else if (category == '精品歌单') {
        final page = await NeteaseApi.instance.highQualityPlaylistPage(
          limit: 50,
          before: highQualityBefore,
        );
        incoming = page.playlists;
        nextHighQualityBefore = page.lasttime;
        nextHasMore = page.more && incoming.isNotEmpty;
      } else {
        // This matches the iOS ExploreView default branch: /playlist/list
        // with the selected category and offset pagination.
        incoming = await NeteaseApi.instance.topPlaylists(
          category: category,
          limit: 50,
          offset: offset,
        );
        nextOffset = offset + 50;
        nextHasMore = incoming.length >= 50 && nextOffset < 500;
      }

      if (!mounted || token != _requestToken) return;
      final existing = {for (final item in playlists) item.id};
      final merged = [
        ...playlists,
        ...incoming.where((item) => !existing.contains(item.id)),
      ];
      setState(() {
        playlists = merged;
        offset = nextOffset;
        highQualityBefore = nextHighQualityBefore;
        hasMore = nextHasMore;
        error = merged.isEmpty ? '当前分类暂时没有返回歌单' : null;
      });
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      // Do not replace an empty playlist catalogue with charts.  That was the
      // old behaviour that made “全部” accidentally look like排行榜.
      setState(() {
        error = playlists.isEmpty ? '$e' : null;
        hasMore = false;
      });
    } finally {
      if (mounted && token == _requestToken) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Future<void> _selectCategory(String value) async {
    if (value == category &&
        (loading ||
            (value != '排行榜' && playlists.isNotEmpty) ||
            (value == '排行榜' && toplists.isNotEmpty))) {
      return;
    }
    final wasCollapsed = _scrollController.hasClients && _scrollController.offset >= kToolbarHeight;
    _saveCategory();
    ++_requestToken;
    final cached = _categoryCache[value];
    setState(() {
      category = value;
      loadingMore = false;
      if (cached != null) {
        playlists = cached.playlists; toplists = cached.toplists;
        offset = cached.offset; highQualityBefore = cached.before;
        hasMore = cached.more; error = cached.error; loading = false;
      }
    });
    if (cached == null) await _load(reset: true);
    if (mounted && wasCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients && _scrollController.offset < kToolbarHeight) {
          _scrollController.jumpTo(kToolbarHeight);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KumoneGlassRefresh(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          KumoneScrollingTabHeader(
            title:
                const Text('精选', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: SizedBox(
                height: 46,
                child: ListView.separated(
                  padding:
                      const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (_, i) {
                    return GlassCategoryChip(menuOptics: true, height: 30,
                        label: categories[i],
                        selected: categories[i] == category,
                        onTap: () => _selectCategory(categories[i]));
                  },
                ),
              ),
            ),
          ),
          if (loading)
            const SliverToBoxAdapter(child: SizedBox(height: 1200,
              child: KumoneLoadingPlaceholder(grid: true)))
          else if (_showToplists)
            if (toplists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: KumoneLoadingText(error ?? '排行榜暂时没有数据')),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, KumoneBottomOverlayInset.of(context) + 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 430,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: toplists.length,
                  itemBuilder: (_, i) => _ToplistCard(
                    item: toplists[i],
                    onTap: () => Navigator.of(context).push(
                      kumonePageRoute(PlaylistPage(
                          id: toplists[i].id,
                          initialCover: toplists[i].coverImgUrl)),
                    ),
                  ),
                ),
              )
          else if (playlists.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: KumoneLoadingText(error ?? '暂时没有歌单')),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, KumoneBottomOverlayInset.of(context) + 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: .74,
                ),
                itemCount: playlists.length,
                itemBuilder: (_, i) => PlaylistCard(
                  item: playlists[i],
                  width: 170,
                  onTap: () => Navigator.of(context).push(
                    kumonePageRoute(PlaylistPage(
                        id: playlists[i].id,
                        initialCover: playlists[i].coverUrl)),
                  ),
                  resolveArtwork: () =>
                      NeteaseApi.instance.playlistCover(playlists[i].id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToplistCard extends StatelessWidget {
  final ToplistItem item;
  final VoidCallback onTap;

  const _ToplistCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: .56),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Artwork(fadeIn: true, 
                url: item.coverImgUrl,
                size: 110,
                radius: 14,
                shadow: false,
                resolveUrl: () => NeteaseApi.instance.playlistCover(item.id),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KumoneLoadingText(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    if (item.updateFrequency != null &&
                        item.updateFrequency!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      KumoneLoadingText(
                        item.updateFrequency!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    ...item.tracks
                        .take(3)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final i = entry.key;
                      final track = entry.value;
                      return Text(
                        '${i + 1}. ${track.first} - ${track.second}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
