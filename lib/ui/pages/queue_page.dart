import '../../core/storage/settings_store.dart';
import '../widgets/liquid_surface.dart';
import '../theme/player_surface_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';
import '../widgets/common.dart';

class QueuePage extends StatelessWidget {
  final Color? primary;
  final Color? secondary;

  const QueuePage({super.key, this.primary, this.secondary});

  @override
  Widget build(BuildContext context) {
    final theme = kumonePlayerSurfaceTheme(Theme.of(context), primary, secondary);
    final foreground = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final secondaryForeground = foreground.withValues(alpha: .72);
    return Theme(data: theme, child: SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: .76,
        minChildSize: .36,
        maxChildSize: .96,
        builder: (context, controller) => _GlassQueueSurface(
          primary: primary,
          secondary: secondary,
          child: QueueListPanel(
            scrollController: controller,
            foregroundColor: foreground,
            secondaryForegroundColor: secondaryForeground,
          ),
        ),
      ),
    ));
  }
}

class _GlassQueueSurface extends StatelessWidget {
  final Color? primary;
  final Color? secondary;
  final Widget child;

  const _GlassQueueSurface({
    required this.child,
    this.primary,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = context.watch<SettingsStore>().menuBackingOpacity;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: KumoneLiquidSurface(
        radius: 28,
        backingOpacity: opacity,
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }
}

class QueueListPanel extends StatelessWidget {
  final ScrollController? scrollController;
  final bool embedded;
  final VoidCallback? onClose;
  final Color? foregroundColor;
  final Color? secondaryForegroundColor;
  final Color? primary;
  final Color? secondary;

  const QueueListPanel({
    super.key,
    this.scrollController,
    this.embedded = false,
    this.onClose,
    this.foregroundColor,
    this.secondaryForegroundColor,
    this.primary,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final dynamicSurface = primary == null
        ? null
        : (Color.lerp(primary, secondary ?? primary!, .42) ?? primary!);
    final foreground = foregroundColor ??
        (dynamicSurface == null
            ? Theme.of(context).colorScheme.onSurface
            : (dynamicSurface.computeLuminance() > .50
                ? Colors.black87
                : Colors.white));
    final secondaryForeground =
        secondaryForegroundColor ?? foreground.withValues(alpha: .72);
    final dividerColor = foreground.withValues(alpha: .14);

    final items = player.playNext +
        (player.currentIndex + 1 < player.queue.length
            ? player.queue.sublist(player.currentIndex + 1)
            : const []);

    return Column(
      children: [
        if (!embedded) const SizedBox(height: 10),
        if (!embedded)
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: .32),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(18, embedded ? 8 : 8, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '播放队列',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: foreground),
                ),
              ),
              Text('${items.length} 首',
                  style: TextStyle(color: secondaryForeground)),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: foreground),
                ),
            ],
          ),
        ),
        if (player.currentTrack != null)
          ListTile(
            leading: Artwork(
              url: player.currentTrack!.album.picUrl,
              size: 42,
              radius: 7,
            ),
            title: Text(
              player.currentTrack!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
            subtitle:
                Text('正在播放', style: TextStyle(color: secondaryForeground)),
          ),
        Divider(height: 1, color: dividerColor),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: scrollController,
            itemCount: items.length,
            onReorderItem: player.reorderUpcoming,
            itemBuilder: (context, i) {
              final track = items[i];
              return Dismissible(
                key: ValueKey('${track.id}-$i'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: Theme.of(context).colorScheme.error,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => player.removeFromQueue(track),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 1),
                  leading:
                      Artwork(url: track.album.picUrl, size: 48, radius: 8),
                  title: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    track.artistNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondaryForeground),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Icon(Icons.drag_handle, color: secondaryForeground),
                  ),
                  onTap: () => player.playQueueItem(track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
