import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../core/storage/settings_store.dart';
import '../widgets/content_fade.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/glass_controls.dart';
import '../widgets/track_title.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/netease_api.dart';
import '../../core/models/models.dart';
import '../../core/player/player_controller.dart';
import '../widgets/common.dart';
import '../widgets/glass_category_chip.dart';
import 'details_page.dart';
import '../theme/app_theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = TextEditingController();
  Timer? debounce;
  SearchResult? result;
  bool loading = false;
  SearchType type = SearchType.all;
  String? submittedQuery;
  final _categoryCache = <String, ({SearchResult result, int offset, bool more})>{};
  Future<void> _selectType(SearchType selected) async {
    if (selected == type && result != null) return;
    if (result != null && submittedQuery != null && !loading) {
      _categoryCache['$submittedQuery:${type.name}'] =
        (result: result!, offset: nextOffset, more: hasMore);
    }
    final cached = _categoryCache['${controller.text.trim()}:${selected.name}'];
    ++requestEpoch;
    setState(() {
      type = selected; loadingMore = false;
      if (cached != null) {
        result = cached.result; nextOffset = cached.offset; hasMore = cached.more;
        submittedQuery = controller.text.trim(); loading = false;
      }
    });
    if (cached == null) await _search();
  }
  int requestEpoch = 0;
  int nextOffset = 0;
  bool loadingMore = false;
  bool hasMore = false;

  int _resultCount(SearchResult page, SearchType selected) => switch (selected) {
    SearchType.songs => page.songs.length,
    SearchType.albums => page.albums.length,
    SearchType.artists => page.artists.length,
    SearchType.playlists => page.playlists.length,
    SearchType.all => 0,
  };

  Future<void> _loadMore() async {
    if (loading || loadingMore || !hasMore || result == null ||
        submittedQuery != controller.text.trim()) {
      return;
    }
    final token = requestEpoch;
    final selectedType = type;
    final query = submittedQuery!;
    setState(() => loadingMore = true);
    try {
      final page = await NeteaseApi.instance.search(query, selectedType,
        limit: 30, offset: nextOffset);
      if (!mounted || token != requestEpoch) return;
      final count = _resultCount(page, selectedType);
      nextOffset += count;
      final old = result!;
      final songIds = old.songs.map((e) => e.id).toSet();
      final albumIds = old.albums.map((e) => e.id).toSet();
      final artistIds = old.artists.map((e) => e.id).toSet();
      final playlistIds = old.playlists.map((e) => e.id).toSet();
      final songs = page.songs.where((e) => songIds.add(e.id)).toList();
      final albums = page.albums.where((e) => albumIds.add(e.id)).toList();
      final artists = page.artists.where((e) => artistIds.add(e.id)).toList();
      var playlists = page.playlists.where((e) => playlistIds.add(e.id)).toList();
      if (playlists.isNotEmpty) {
        playlists = await NeteaseApi.instance.hydratePlaylistCovers(playlists);
      }
      if (!mounted || token != requestEpoch) return;
      result = SearchResult(songs: [...old.songs, ...songs],
        albums: [...old.albums, ...albums], artists: [...old.artists, ...artists],
        playlists: [...old.playlists, ...playlists]);
      hasMore = count >= 30 &&
          (songs.isNotEmpty || albums.isNotEmpty || artists.isNotEmpty || playlists.isNotEmpty);
    } catch (_) {
      if (mounted && token == requestEpoch) {
        context.read<PlayerController>().showNotice('加载更多失败，请继续滑动重试');
      }
    } finally {
      if (mounted && token == requestEpoch) setState(() => loadingMore = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    final query = controller.text.trim();
    if (query.isEmpty) return;
    debounce?.cancel();
    final token = ++requestEpoch;
    final selectedType = type;
    setState(() { loading = true; loadingMore = false; hasMore = false; });
    try {
      SearchResult loaded;
      if (selectedType == SearchType.all) {
        final values = await Future.wait([
          NeteaseApi.instance.search(query, SearchType.songs, limit: 30),
          NeteaseApi.instance.search(query, SearchType.albums, limit: 12),
          NeteaseApi.instance.search(query, SearchType.artists, limit: 12),
          NeteaseApi.instance.search(query, SearchType.playlists, limit: 12),
        ]);
        loaded = SearchResult(
          songs: values[0].songs,
          albums: values[1].albums,
          artists: values[2].artists,
          playlists: await NeteaseApi.instance
              .hydratePlaylistCovers(values[3].playlists),
        );
      } else {
        loaded = await NeteaseApi.instance.search(query, selectedType);
      }
      if ((selectedType == SearchType.playlists || selectedType == SearchType.all) &&
          loaded.playlists.isNotEmpty) {
        final hydrated =
            await NeteaseApi.instance.hydratePlaylistCovers(loaded.playlists);
        loaded = SearchResult(
          songs: loaded.songs,
          albums: loaded.albums,
          artists: loaded.artists,
          playlists: hydrated,
        );
      }
      if (!mounted || token != requestEpoch) return;
      result = loaded;
      submittedQuery = query;
      nextOffset = _resultCount(loaded, selectedType);
      hasMore = selectedType != SearchType.all && nextOffset >= 30;
    } catch (e) {
      if (mounted && token == requestEpoch) {
        context.read<PlayerController>().showNotice('搜索失败：$e');
      }
    }
    if (mounted && token == requestEpoch) setState(() => loading = false);
  }

  void _scheduleSearch() {
    requestEpoch++;
    loadingMore = false;
    hasMore = false;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), _search);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final data = result;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: NestedScrollView(
      physics: const ClampingScrollPhysics(),
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        KumoneScrollingTabHeader(
          contentScrolled: innerBoxIsScrolled,
          rightInset: 16,
          title: Center(child: KumoneGlassSearchField(
            height: 40,
            controller: controller,
            decoration: const InputDecoration(
              hintText: '搜索歌曲、歌手、专辑或歌单',
              prefixIcon: Icon(Icons.search)),
            onChanged: (_) => _scheduleSearch(),
            onSubmitted: (_) => _search(),
          )),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: LayoutBuilder(builder: (context, constraints) =>
                  SingleChildScrollView(scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth:
                        MediaQuery.sizeOf(context).width >= 600 &&
                            (context.watch<SettingsStore?>()?.wideTopTabs ?? false)
                          ? 0 : constraints.maxWidth),
                      child: Row(mainAxisSize: MainAxisSize.min,
                        spacing: MediaQuery.sizeOf(context).width >= 600 &&
                            (context.watch<SettingsStore?>()?.wideTopTabs ?? false) ? 20 : 0,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [for (final value in SearchType.values)
                          Builder(builder: (context) {
                  final selected = value == type;
                  return GlassCategoryChip(menuOptics: true, height: 30,
                    label: switch (value) {
                      SearchType.all => '综合',
                      SearchType.songs => '单曲',
                      SearchType.albums => '专辑',
                      SearchType.artists => '歌手',
                      SearchType.playlists => '歌单',
                    },
                    selected: selected,
                    onTap: () {
                      _selectType(value);
                    },
                  );
                          }),
                        ]),
                    ),
                  )),
              ),
            ),
          ),
        ),
      ],
      body: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.metrics.axis == Axis.vertical &&
              event.metrics.extentAfter < 400 &&
              (event is ScrollUpdateNotification || event is OverscrollNotification)) {
            unawaited(_loadMore());
          }
          return false;
        },
        child: Stack(children: [Positioned.fill(child: loading
          ? KumoneLoadingPlaceholder(grid: type != SearchType.all && type != SearchType.songs,
              circle: type == SearchType.artists)
          : data == null
              ? const Center(child: Text('输入关键词开始搜索'))
              : data.songs.isEmpty &&
                      data.albums.isEmpty &&
                      data.artists.isEmpty &&
                      data.playlists.isEmpty
                  ? _SearchEmpty(query: submittedQuery ?? controller.text)
                  : _Results(
                      data: data,
                      type: type,
                      player: player,
                      onSelectType: _selectType,
                    )),
        ])),
    ));
  }
}

class _SearchEmpty extends StatelessWidget {
  final String query;
  const _SearchEmpty({required this.query});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('没有找到“$query”相关内容',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('可以换一个关键词再试试',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final SearchResult data;
  final SearchType type;
  final PlayerController player;
  final ValueChanged<SearchType> onSelectType;

  const _Results({
    required this.data,
    required this.type,
    required this.player,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    if (type == SearchType.albums || type == SearchType.artists ||
        type == SearchType.playlists) {
      return KumoneSearchResultGrid(data: data, type: type);
    }
    return ListView(
          scrollCacheExtent: ScrollCacheExtent.pixels((context.watch<SettingsStore?>()?.listLazyLoading ?? true) ? 0 : 1000),
      physics: const ClampingScrollPhysics(),
      padding:
          EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24),
      children: [
        if (type == SearchType.all) ...[
          if (data.songs.isNotEmpty) ...[
            SectionHeader(title: '单曲', topSpacing: 0, bottomSpacing: 4, showChevron: true, onTap: () => onSelectType(SearchType.songs)),
            ...data.songs.take(20).map(
                  (track) => TrackActionMenu(
                    track: track,
                    showButton: false,
                    child: HomeAppear(child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      leading:
                          Artwork(fadeIn: true, url: track.album.picUrl, size: 52, radius: 9),
                      title: KumoneTrackTitle(trackId: track.id, title: track.name),
                      subtitle: KumoneLoadingText(track.artistNames),
                      trailing: KumoneLoadingText(
                        formatDuration(track.duration),
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      onTap: () => player.playTrack(track),
                    )),
                    onOpenAlbum: (album) => Navigator.of(context)
                        .push(kumonePageRoute(AlbumPage(id: album.id))),
                    onOpenArtist: (artist) => Navigator.of(context)
                        .push(kumonePageRoute(ArtistPage(id: artist.id))),
                  ),
                ),
          ],
          if (data.albums.isNotEmpty) ...[
            SectionHeader(title: '专辑', topSpacing: 20, bottomSpacing: 4, showChevron: true, onTap: () => onSelectType(SearchType.albums)),
            ...data.albums.take(8).map(
                  (album) => CollectionActionMenu(id: album.id, onOpenArtist: (id) => Navigator.of(context).push(kumonePageRoute(ArtistPage(id: id))), child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Artwork(fadeIn: true, url: album.picUrl, size: 52, radius: 9),
                    title: KumoneLoadingText(album.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: KumoneLoadingText(album.artistName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context)
                        .push(kumonePageRoute(AlbumPage(id: album.id))),
                  )),
                ),
          ],
          if (data.artists.isNotEmpty) ...[
            SectionHeader(title: '歌手', topSpacing: 20, bottomSpacing: 4, showChevron: true, onTap: () => onSelectType(SearchType.artists)),
            ...data.artists.take(8).map(
                  (artist) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 68,
                    minVerticalPadding: 8,
                    leading: Artwork(fadeIn: true, 
                        url: artist.picUrl, size: 52, radius: 26, circle: true),
                    title: KumoneLoadingText(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context)
                        .push(kumonePageRoute(ArtistPage(id: artist.id))),
                  ),
                ),
          ],
          if (data.playlists.isNotEmpty) ...[
            SectionHeader(title: '歌单', topSpacing: 20, bottomSpacing: 4, showChevron: true, onTap: () => onSelectType(SearchType.playlists)),
            ...data.playlists.take(8).map(
                  (playlist) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    minTileHeight: 68,
                    minVerticalPadding: 8,
                    leading: Artwork(fadeIn: true, 
                      url: playlist.coverUrl,
                      resolveUrl: () =>
                          NeteaseApi.instance.playlistCover(playlist.id),
                      size: 52,
                      radius: 9,
                    ),
                    title: KumoneLoadingText(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${playlist.trackCount} 首'),
                    onTap: () => Navigator.of(context).push(kumonePageRoute(
                        PlaylistPage(
                            id: playlist.id, initialCover: playlist.coverUrl))),
                  ),
                ),
          ],
        ],
        if (type == SearchType.songs)
          ...data.songs.map(
            (track) => TrackActionMenu(
              track: track,
              showButton: false,
              child: HomeAppear(child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Artwork(fadeIn: true, 
                  url: track.album.picUrl,
                  size: 52,
                  radius: 9,
                ),
                title: KumoneTrackTitle(trackId: track.id, title: track.name),
                subtitle: KumoneLoadingText(track.artistNames),
                trailing: KumoneLoadingText(
                  formatDuration(track.duration),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => player.playTrack(track),
              )),
              onOpenAlbum: (album) => Navigator.of(context)
                  .push(kumonePageRoute(AlbumPage(id: album.id))),
              onOpenArtist: (artist) => Navigator.of(context)
                  .push(kumonePageRoute(ArtistPage(id: artist.id))),
            ),
          ),
        if (type == SearchType.albums)
          ...data.albums.map(
            (album) => CollectionActionMenu(id: album.id, onOpenArtist: (id) => Navigator.of(context).push(kumonePageRoute(ArtistPage(id: id))), child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Artwork(fadeIn: true, url: album.picUrl, size: 52, radius: 9),
              title: KumoneLoadingText(album.name),
              subtitle: KumoneLoadingText(album.artistName),
              onTap: () => Navigator.of(context).push(
                kumonePageRoute(AlbumPage(id: album.id)),
              ),
            )),
          ),
        if (type == SearchType.artists)
          ...data.artists.map(
            (artist) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Artwork(fadeIn: true, 
                url: artist.picUrl,
                size: 52,
                radius: 26,
                circle: true,
              ),
              title: KumoneLoadingText(artist.name),
              onTap: () => Navigator.of(context).push(
                kumonePageRoute(ArtistPage(id: artist.id)),
              ),
            ),
          ),
        if (type == SearchType.playlists)
          ...data.playlists.map(
            (playlist) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Artwork(fadeIn: true, 
                url: playlist.coverUrl,
                resolveUrl: () =>
                    NeteaseApi.instance.playlistCover(playlist.id),
                size: 52,
                radius: 9,
              ),
              title: KumoneLoadingText(playlist.name),
              subtitle: Text('${playlist.trackCount} 首'),
              onTap: () => Navigator.of(context).push(
                kumonePageRoute(PlaylistPage(id: playlist.id)),
              ),
            ),
          ),
      ],
    );
  }
}

class KumoneSearchResultGrid extends StatelessWidget {
  final SearchResult data;
  final SearchType type;
  const KumoneSearchResultGrid({super.key, required this.data, required this.type});
  @override
  Widget build(BuildContext context) {
    final artist = type == SearchType.artists;
    final album = type == SearchType.albums;
    final count = artist ? data.artists.length : album ? data.albums.length : data.playlists.length;
    return GridView.builder(
          scrollCacheExtent: ScrollCacheExtent.pixels((context.watch<SettingsStore?>()?.listLazyLoading ?? true) ? 0 : 1000),
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16,
        KumoneBottomOverlayInset.of(context) + 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190, crossAxisSpacing: 14,
        mainAxisSpacing: 18, childAspectRatio: .74,
        mainAxisExtent: artist ? 166 : null),
      itemCount: count,
      itemBuilder: (context, index) => LayoutBuilder(builder: (context, cell) {
        final name = artist ? data.artists[index].name
            : album ? data.albums[index].name : data.playlists[index].name;
        final picture = artist ? data.artists[index].picUrl
            : album ? data.albums[index].picUrl : data.playlists[index].coverUrl;
        final imageSize = artist ? cell.maxWidth.clamp(0.0, 128.0) : cell.maxWidth;
        final tile = KumoneInteractive(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(kumonePageRoute(
            artist ? ArtistPage(id: data.artists[index].id)
              : album ? AlbumPage(id: data.albums[index].id)
              : PlaylistPage(id: data.playlists[index].id,
                  initialCover: data.playlists[index].coverUrl))),
          child: Column(crossAxisAlignment: artist ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch, children: [
            Center(child: Artwork(fadeIn: true, url: picture, size: imageSize,
              radius: artist ? imageSize / 2 : 14, circle: artist, shadow: false,
              resolveUrl: artist ? () => NeteaseApi.instance.artistCover(data.artists[index].id)
                : album ? null : () => NeteaseApi.instance.playlistCover(data.playlists[index].id))),
            const SizedBox(height: 8),
            SizedBox(width: imageSize, child: KumoneLoadingText(name,
              maxLines: artist || album ? 1 : 2, overflow: TextOverflow.ellipsis,
              textAlign: artist ? TextAlign.center : TextAlign.start,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            if (album) ...[
              const SizedBox(height: 3),
              KumoneLoadingText(data.albums[index].artistName, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ]));
        return album ? CollectionActionMenu(id: data.albums[index].id,
          onOpenArtist: (id) => Navigator.of(context).push(kumonePageRoute(ArtistPage(id: id))),
          child: tile) : tile;
      }),
    );
  }
}
