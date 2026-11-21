import '../widgets/glass_refresh.dart';
import '../widgets/glass_category_chip.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/storage/account_store.dart';
import '../widgets/common.dart';
import '../theme/app_theme.dart';
import 'details_page.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  int tab = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = context.read<AccountStore>();
    if (!account.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    await account.refreshSublists();
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountStore>();
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(children: [
                  Expanded(child: GlassCategoryChip(menuOptics: true,
                    label: '专辑', selected: tab == 0,
                    onTap: () => setState(() => tab = 0),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GlassCategoryChip(menuOptics: true,
                    label: '歌手', selected: tab == 1,
                    onTap: () => setState(() => tab = 1),
                  )),
                ]),
              ),
            ),
            if (loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (tab == 0)
              _albumSliver(account.likedAlbums)
            else
              _artistSliver(account.likedArtists),
            SliverPadding(padding: EdgeInsets.only(bottom: KumoneBottomOverlayInset.of(context) + 24)),
          ],
        ),
      ),
    );
  }

  Widget _albumSliver(List<AlbumSummary> albums) {
    if (albums.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyCollection(icon: Icons.album_outlined, title: '还没有收藏专辑'),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 18,
          crossAxisSpacing: 14,
          childAspectRatio: .70,
        ),
        itemCount: albums.length,
        itemBuilder: (_, i) {
          final album = albums[i];
          return KumoneInteractive(
            onTap: () => Navigator.of(context).push(kumonePageRoute(AlbumPage(id: album.id))),
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(aspectRatio: 1.08, child: Artwork(url: album.picUrl, radius: 14, shadow: false, size: 190)),
                const SizedBox(height: 8),
                Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (album.artistName.isNotEmpty)
                  Text(album.artistName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _artistSliver(List<ArtistSummary> artists) {
    if (artists.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyCollection(icon: Icons.mic_none_rounded, title: '还没有关注歌手'),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 20,
          crossAxisSpacing: 14,
          childAspectRatio: .86,
        ),
        itemCount: artists.length,
        itemBuilder: (_, i) {
          final artist = artists[i];
          return KumoneInteractive(
            onTap: () => Navigator.of(context).push(kumonePageRoute(ArtistPage(id: artist.id))),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Artwork(url: artist.picUrl, size: 132, radius: 66, circle: true, shadow: false),
                  ),
                ),
                const SizedBox(height: 7),
                Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  final IconData icon;
  final String title;
  const _EmptyCollection({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
