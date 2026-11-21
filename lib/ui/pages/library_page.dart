import '../../core/player/player_controller.dart';
import '../widgets/glass_playlist_dialog.dart';
import '../widgets/glass_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/account_store.dart';
import '../widgets/common.dart';
import '../widgets/liquid_surface.dart';
import '../../core/storage/settings_store.dart';
import '../theme/app_theme.dart';
import 'details_page.dart';
import 'login_page.dart';
import 'settings_page.dart';
import 'library_media_pages.dart';
import 'liked_page.dart';
import 'collections_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountStore>();

    if (!account.isLoggedIn) {
      return Scaffold(
        appBar: KumoneGlassAppBar(title: const Text('我的'), actions: [
          IconButton(
              onPressed: () => Navigator.of(context)
                  .push(kumonePageRoute(const SettingsPage(), settings: const RouteSettings(name: '/settings'))),
              icon: const Icon(Icons.settings_outlined)),
        ]),
        body: ListView(children: [
          ListTile(
              leading: const Icon(Icons.login),
              title: const Text('登录后查看在线音乐库'),
              onTap: () => Navigator.of(context)
                  .push(kumonePageRoute(const LoginPage()))),
        ]),
      );
    }

    final profile = account.profile!;
    return KumoneGlassRefresh(
      onRefresh: account.refreshLibrary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          KumoneScrollingTabHeader(
            title: const Text(
              '我的',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            actions: [
              IconButton(
                tooltip: '设置',
                onPressed: () => Navigator.of(context).push(
                  kumonePageRoute(const SettingsPage(), settings: const RouteSettings(name: '/settings')),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Artwork(
                    url: profile.avatarUrl,
                    resolveUrl: () => account.api.userAvatar(profile.userId),
                    size: 64,
                    radius: 32,
                    circle: true,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.nickname,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          account.vipType > 0 ? '黑胶 / VIP' : '普通账号',
                          style: TextStyle(
                            color: account.vipType > 0
                                ? const Color(0xFFD0923C)
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth;
                  return KumoneLiquidSurface(
                    radius: 24,
                    blur: context.watch<SettingsStore>().quickEntryBlur,
                    backingOpacity:
                        context.watch<SettingsStore>().menuBackingOpacity,
                    child: Column(
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _Entry(
                            icon: Icons.favorite,
                            title: '我喜欢的音乐',
                            onTap: () => Navigator.of(context).push(
                              kumonePageRoute(const LikedSongsPage()),
                            ),
                          ),
                        ),
                        SizedBox(
                            width: itemWidth,
                            child: _Entry(
                              icon: Icons.calendar_month_outlined,
                              title: '每日推荐',
                              onTap: () => Navigator.of(context)
                                  .push(kumonePageRoute(const DailyPage())),
                            )),
                        SizedBox(
                          width: itemWidth,
                          child: _Entry(
                            icon: Icons.collections_bookmark_outlined,
                            title: '我的收藏',
                            onTap: () => Navigator.of(context).push(
                              kumonePageRoute(const CollectionsPage()),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _Entry(
                            icon: Icons.library_music_outlined,
                            title: '收藏的歌单',
                            onTap: () => Navigator.of(context).push(
                              kumonePageRoute(
                                const _PlaylistListPage(subscribed: true),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _Entry(
                            icon: Icons.history,
                            title: '最近播放',
                            onTap: () => Navigator.of(context).push(
                              kumonePageRoute(const RecentPage()),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _Entry(
                            icon: Icons.cloud_outlined,
                            title: '音乐云盘',
                            onTap: () => Navigator.of(context).push(
                              kumonePageRoute(const CloudPage()),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _Entry(
                            icon: Icons.queue_music,
                            title: '创建的歌单',
                            onTap: () => Navigator.of(context).push(
                              kumonePageRoute(
                                const _PlaylistListPage(subscribed: false),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
              padding: EdgeInsets.only(
                  bottom: KumoneBottomOverlayInset.of(context) + 24)),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _Entry({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: radius,
            border: Border(
                bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .16),
              width: .5,
            )),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistListPage extends StatefulWidget {
  final bool subscribed;

  const _PlaylistListPage({required this.subscribed});

  @override
  State<_PlaylistListPage> createState() => _PlaylistListPageState();
}

class _PlaylistListPageState extends State<_PlaylistListPage> {
  Future<void> _refresh() => context.read<AccountStore>().refreshLibrary();

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountStore>();
    final playlists = widget.subscribed
        ? account.subscribedPlaylists
        : account.createdPlaylists;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KumoneGlassAppBar(
        title: const SizedBox.shrink(),
        actions: [
          if (!widget.subscribed)
            IconButton(
              tooltip: '新建歌单',
              onPressed: () => _createPlaylistFromList(context, account),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: KumoneGlassRefresh.adaptive(
        onRefresh: _refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: EdgeInsets.only(
            top: kumoneToolbarInset(context) + 8,
            bottom: KumoneBottomOverlayInset.of(context) + 24,
          ),
          itemCount: playlists.isEmpty ? 1 : playlists.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            if (playlists.isEmpty) {
              return SizedBox(
                height: MediaQuery.sizeOf(context).height * .55,
                child: Center(
                  child: Text(widget.subscribed ? '还没有收藏歌单' : '还没有创建歌单'),
                ),
              );
            }
            final playlist = playlists[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              leading: Artwork(
                url: playlist.coverUrl,
                resolveUrl: () => account.api.playlistCover(playlist.id),
                size: 52,
                radius: 10,
              ),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${playlist.trackCount} 首'
                '${playlist.creator?.nickname.isNotEmpty == true ? ' · ${playlist.creator!.nickname}' : ''}',
              ),
              trailing: widget.subscribed
                  ? null
                  : IconButton(
                      tooltip: '删除歌单',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deletePlaylistFromList(
                        context,
                        account,
                        playlist.id,
                        playlist.name,
                      ),
                    ),
              onTap: () => Navigator.of(context).push(
                kumonePageRoute(
                  PlaylistPage(
                    id: playlist.id,
                    initialCover: playlist.coverUrl,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<void> _createPlaylistFromList(
  BuildContext context,
  AccountStore account,
) async {
  final controller = TextEditingController();
  final name = await kumoneDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: KumoneLiquidSurface(
          radius: 24,
          interactive: false,
          blur: context.read<SettingsStore>().songMenuBlur,
          backingOpacity: context.read<SettingsStore>().menuBackingOpacity,
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft,
              child: Text('新建歌单', style: Theme.of(dialogContext).textTheme.titleLarge)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(hintText: '歌单名称'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(
                  dialogContext, controller.text.trim()), child: const Text('创建')),
            ]),
          ]),
        ),
      ),
    ),
  );
  final trimmed = name?.trim() ?? '';
  controller.dispose();
  if (trimmed.isEmpty) return;
  try {
    final id = await account.api.createPlaylist(trimmed);
    if (id == null) throw const FormatException('创建歌单失败');
    await account.refreshLibrary();
    if (context.mounted) {
      context.read<PlayerController>().showNotice('歌单创建成功');
    }
  } catch (e) {
    if (context.mounted) {
      context.read<PlayerController>().showNotice('$e');
    }
  }
}

Future<void> _deletePlaylistFromList(
  BuildContext context,
  AccountStore account,
  int id,
  String name,
) async {
  final confirmed = await kumoneDialog<bool>(
    context: context,
    builder: (dialogContext) => KumoneGlassPlaylistDialog(
      title: const Text('删除歌单？'),
      content: Text('将删除「$name」，此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await account.api.deletePlaylist(id);
    await account.refreshLibrary();
    if (context.mounted) {
      context.read<PlayerController>().showNotice('歌单已删除');
    }
  } catch (e) {
    if (context.mounted) {
      context.read<PlayerController>().showNotice('$e');
    }
  }
}
