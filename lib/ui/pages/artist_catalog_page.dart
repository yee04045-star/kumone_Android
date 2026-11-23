import '../widgets/content_fade.dart';
import '../widgets/loading_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/netease_api.dart';
import '../../core/models/models.dart';
import '../../core/player/player_controller.dart';
import '../widgets/common.dart';
import '../theme/app_theme.dart';
import '../widgets/track_title.dart';
import 'details_page.dart';

class ArtistCatalogPage extends StatefulWidget {
  final int artistId;
  final bool albums;
  const ArtistCatalogPage({super.key, required this.artistId, this.albums = false});
  @override State<ArtistCatalogPage> createState() => _ArtistCatalogPageState();
}
class _ArtistCatalogPageState extends State<ArtistCatalogPage> {
  final scroll = ScrollController();
  final songs = <Track>[];
  final albums = <AlbumSummary>[];
  bool busy = false, more = true;
  int offset = 0;
  String? error;
  @override void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 400) load();
    });
    load();
  }
  Future<void> load() async {
    if (busy || !more) return;
    setState(() { busy = true; error = null; });
    try {
      final api = NeteaseApi.instance;
      final batch = widget.albums
          ? await api.artistAlbums(widget.artistId, limit: 30, offset: offset)
          : await api.artistSongs(widget.artistId, limit: 30, offset: offset);
      if (!mounted) return;
      offset += batch.length;
      if (widget.albums) {
        final ids = albums.map((a) => a.id).toSet();
        final fresh = batch.cast<AlbumSummary>().where((a) => ids.add(a.id)).toList();
        albums.addAll(fresh);
        more = batch.length >= 30 && fresh.isNotEmpty;
      } else {
        final ids = songs.map((s) => s.id).toSet();
        final fresh = batch.cast<Track>().where((s) => ids.add(s.id)).toList();
        songs.addAll(fresh);
        more = batch.length >= 30 && fresh.isNotEmpty;
      }
    } catch (_) {
      if (mounted) {
        error = '加载失败';
        context.read<PlayerController>().showNotice('加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override void dispose() { scroll.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Scaffold(extendBodyBehindAppBar: true,
      appBar: const KumoneGlassAppBar(title: SizedBox.shrink()),
      body: CustomScrollView(controller: scroll, slivers: [
        SliverToBoxAdapter(child: SizedBox(height: kumoneToolbarInset(context))),
        if (widget.albums) SliverPadding(padding: const EdgeInsets.all(16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190, crossAxisSpacing: 14,
              mainAxisSpacing: 18, childAspectRatio: .74),
            itemCount: albums.length, itemBuilder: (context, i) {
              final album = albums[i];
              return KumoneInteractive(borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(kumonePageRoute(
                  AlbumPage(id: album.id, sourceArtistId: widget.artistId))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [AspectRatio(aspectRatio: 1, child: Artwork(fadeIn: true, 
                    url: album.picUrl, size: 190, radius: 14, shadow: false)),
                    const SizedBox(height: 8),
                    KumoneLoadingText(album.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    KumoneLoadingText(album.artistName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]));
            }))
        else SliverList.builder(itemCount: songs.length, itemBuilder: (context, i) {
          final song = songs[i];
          return TrackActionMenu(track: song, showButton: false,
            onOpenAlbum: (a) => Navigator.of(context).push(kumonePageRoute(AlbumPage(id: a.id))),
            onOpenArtist: (a) => Navigator.of(context).push(kumonePageRoute(ArtistPage(id: a.id))),
            child: ListTile(leading: Artwork(fadeIn: true, url: song.album.picUrl, size: 52, radius: 9),
              title: KumoneTrackTitle(trackId: song.id, title: song.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: KumoneLoadingText(song.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: KumoneLoadingText(formatDuration(song.duration)),
              onTap: () => player.playTracks(songs, index: i)));
        }),
        if (busy && songs.isEmpty && albums.isEmpty) SliverToBoxAdapter(
          child: SizedBox(height: 900, child: KumoneLoadingPlaceholder(grid: widget.albums)))
        else if (songs.isEmpty && albums.isEmpty && error == null)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24),
            child: Center(child: Text('暂无内容'))))
        else if (error != null) SliverToBoxAdapter(child: Center(
          child: TextButton(onPressed: load, child: const Text('加载失败，点击重试')))),
        SliverToBoxAdapter(child: SizedBox(height: KumoneBottomOverlayInset.of(context) + 24)),
      ]));
  }
}
