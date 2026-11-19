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

  @override
  void dispose() {
    controller.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    final query = controller.text.trim();
    if (query.isEmpty) return;
    setState(() => loading = true);
    try {
      SearchResult loaded;
      if (type == SearchType.all) {
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
        loaded = await NeteaseApi.instance.search(query, type);
      }
      if ((type == SearchType.playlists || type == SearchType.all) &&
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
      result = loaded;
      submittedQuery = query;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
    if (mounted) setState(() => loading = false);
  }

  void _scheduleSearch() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), _search);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final data = result;
    final scheme = Theme.of(context).colorScheme;

    return NestedScrollView(
      physics: const BouncingScrollPhysics(),
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        KumoneGlassSliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          toolbarHeight: 62,
          titleSpacing: 8,
          title: SearchBar(
            controller: controller,
            hintText: '搜索歌曲、歌手、专辑或歌单',
            leading: const Icon(Icons.search),
            trailing: [
              IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
            backgroundColor: WidgetStatePropertyAll(
              scheme.surface.withValues(alpha: .16),
            ),
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            onChanged: (_) => _scheduleSearch(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: SizedBox(
              height: 54,
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: SearchType.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (_, i) {
                  final value = SearchType.values[i];
                  final selected = value == type;
                  return GlassCategoryChip(
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
                },
              ),
            ),
          ),
        ),
      ],
      body: loading
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
                    ),
    );
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

  const _Results({
    required this.data,
    required this.type,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24),
      children: [
        if (type == SearchType.all) ...[
          if (data.songs.isNotEmpty) ...[
            const SectionHeader(title: '单曲'),
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
            const SectionHeader(title: '专辑'),
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
            const SectionHeader(title: '歌手'),
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
            const SectionHeader(title: '歌单'),
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
