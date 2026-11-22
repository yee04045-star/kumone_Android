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
  int requestEpoch = 0;
  int nextOffset = 0;
  bool loadingMore = false;
  bool hasMore = false;

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
      final count = selectedType == SearchType.songs ? page.songs.length : page.albums.length;
      nextOffset += count;
      final old = result!;
      final songIds = old.songs.map((e) => e.id).toSet();
      final albumIds = old.albums.map((e) => e.id).toSet();
      final songs = page.songs.where((e) => songIds.add(e.id)).toList();
      final albums = page.albums.where((e) => albumIds.add(e.id)).toList();
      result = SearchResult(songs: [...old.songs, ...songs],
        albums: [...old.albums, ...albums], artists: old.artists, playlists: old.playlists);
      hasMore = count >= 30 && (songs.isNotEmpty || albums.isNotEmpty);
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
      nextOffset = selectedType == SearchType.songs ? loaded.songs.length : loaded.albums.length;
      hasMore = (selectedType == SearchType.songs || selectedType == SearchType.albums) && nextOffset >= 30;
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
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: Row(mainAxisSize: MainAxisSize.min,
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
                      setState(() => type = value);
                      _search();
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
          ? const Center(child: CircularProgressIndicator())
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
                      onSelectType: (selected) { setState(() => type = selected); _search(); },
                    )),
          if (loadingMore) const Positioned(left: 0, right: 0, bottom: 8,
            child: Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)))),
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
      physics: const ClampingScrollPhysics(),
      padding:
          EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24),
      children: [
        if (type == SearchType.all) ...[
          if (data.songs.isNotEmpty) ...[
            SectionHeader(title: '单曲', showChevron: true, onTap: () => onSelectType(SearchType.songs)),
            ...data.songs.take(20).map(
                  (track) => TrackActionMenu(
                    track: track,
                    showButton: false,
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      leading:
                          Artwork(url: track.album.picUrl, size: 52, radius: 9),
                      title: KumoneTrackTitle(trackId: track.id, title: track.name),
                      subtitle: Text(track.artistNames),
                      trailing: Text(
                        formatDuration(track.duration),
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      onTap: () => player.playTrack(track),
                    ),
                    onOpenAlbum: (album) => Navigator.of(context)
                        .push(kumonePageRoute(AlbumPage(id: album.id))),
                    onOpenArtist: (artist) => Navigator.of(context)
                        .push(kumonePageRoute(ArtistPage(id: artist.id))),
                  ),
                ),
          ],
          if (data.albums.isNotEmpty) ...[
            SectionHeader(title: '专辑', showChevron: true, onTap: () => onSelectType(SearchType.albums)),
            ...data.albums.take(8).map(
                  (album) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Artwork(url: album.picUrl, size: 52, radius: 9),
                    title: Text(album.name),
                    subtitle: Text(album.artistName),
                    onTap: () => Navigator.of(context)
                        .push(kumonePageRoute(AlbumPage(id: album.id))),
                  ),
                ),
          ],
          if (data.artists.isNotEmpty) ...[
            SectionHeader(title: '歌手', showChevron: true, onTap: () => onSelectType(SearchType.artists)),
            ...data.artists.take(8).map(
                  (artist) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Artwork(
                        url: artist.picUrl, size: 52, radius: 26, circle: true),
                    title: Text(artist.name),
                    onTap: () => Navigator.of(context)
                        .push(kumonePageRoute(ArtistPage(id: artist.id))),
                  ),
                ),
          ],
          if (data.playlists.isNotEmpty) ...[
            SectionHeader(title: '歌单', showChevron: true, onTap: () => onSelectType(SearchType.playlists)),
            ...data.playlists.take(8).map(
                  (playlist) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Artwork(
                      url: playlist.coverUrl,
                      resolveUrl: () =>
                          NeteaseApi.instance.playlistCover(playlist.id),
                      size: 52,
                      radius: 9,
                    ),
                    title: Text(playlist.name),
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
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Artwork(
                  url: track.album.picUrl,
                  size: 52,
                  radius: 9,
                ),
                title: KumoneTrackTitle(trackId: track.id, title: track.name),
                subtitle: Text(track.artistNames),
                trailing: Text(
                  formatDuration(track.duration),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => player.playTrack(track),
              ),
              onOpenAlbum: (album) => Navigator.of(context)
                  .push(kumonePageRoute(AlbumPage(id: album.id))),
              onOpenArtist: (artist) => Navigator.of(context)
                  .push(kumonePageRoute(ArtistPage(id: artist.id))),
            ),
          ),
        if (type == SearchType.albums)
          ...data.albums.map(
            (album) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Artwork(url: album.picUrl, size: 52, radius: 9),
              title: Text(album.name),
              subtitle: Text(album.artistName),
              onTap: () => Navigator.of(context).push(
                kumonePageRoute(AlbumPage(id: album.id)),
              ),
            ),
          ),
        if (type == SearchType.artists)
          ...data.artists.map(
            (artist) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Artwork(
                url: artist.picUrl,
                size: 52,
                radius: 26,
                circle: true,
              ),
              title: Text(artist.name),
              onTap: () => Navigator.of(context).push(
                kumonePageRoute(ArtistPage(id: artist.id)),
              ),
            ),
          ),
        if (type == SearchType.playlists)
          ...data.playlists.map(
            (playlist) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Artwork(
                url: playlist.coverUrl,
                resolveUrl: () =>
                    NeteaseApi.instance.playlistCover(playlist.id),
                size: 52,
                radius: 9,
              ),
              title: Text(playlist.name),
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
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16,
        KumoneBottomOverlayInset.of(context) + 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190, crossAxisSpacing: 14,
        mainAxisSpacing: 18, childAspectRatio: .74),
      itemCount: count,
      itemBuilder: (context, index) => LayoutBuilder(builder: (context, cell) {
        final name = artist ? data.artists[index].name
            : album ? data.albums[index].name : data.playlists[index].name;
        final picture = artist ? data.artists[index].picUrl
            : album ? data.albums[index].picUrl : data.playlists[index].coverUrl;
        final imageSize = artist ? cell.maxWidth.clamp(0.0, 128.0) : cell.maxWidth;
        return KumoneInteractive(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(kumonePageRoute(
            artist ? ArtistPage(id: data.artists[index].id)
              : album ? AlbumPage(id: data.albums[index].id)
              : PlaylistPage(id: data.playlists[index].id,
                  initialCover: data.playlists[index].coverUrl))),
          child: Column(crossAxisAlignment: artist ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch, children: [
            Center(child: Artwork(url: picture, size: imageSize,
              radius: artist ? imageSize / 2 : 14, circle: artist, shadow: false,
              resolveUrl: artist ? () => NeteaseApi.instance.artistCover(data.artists[index].id)
                : album ? null : () => NeteaseApi.instance.playlistCover(data.playlists[index].id))),
            const SizedBox(height: 8),
            SizedBox(width: imageSize, child: Text(name,
              maxLines: artist || album ? 1 : 2, overflow: TextOverflow.ellipsis,
              textAlign: album ? TextAlign.start : TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            if (album) ...[
              const SizedBox(height: 3),
              Text(data.albums[index].artistName, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ]));
      }),
    );
  }
}
