import 'dart:ui' as ui;
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
      child: _QueueResizeHost(primary: primary, secondary: secondary,
        foreground: foreground, secondaryForeground: secondaryForeground),
    ));
  }
}

class _QueueResizeHost extends StatefulWidget {
  final Color? primary, secondary;
  final Color foreground, secondaryForeground;
  const _QueueResizeHost({this.primary, this.secondary,
    required this.foreground, required this.secondaryForeground});
  @override State<_QueueResizeHost> createState() => _QueueResizeHostState();
}
class _QueueResizeHostState extends State<_QueueResizeHost>
    with SingleTickerProviderStateMixin {
  double fraction = .76;
  double drag = 0;
  double slide = 0;
  double startFraction = .76;
  late final motion = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 240));
  Future<void> settle(double target, {bool dismiss = false}) async {
    final from = fraction, fromSlide = slide;
    void tick() {
      final t = Curves.easeOutCubic.transform(motion.value);
      setState(() {
        fraction = from + (target - from) * t;
        slide = fromSlide + ((dismiss ? MediaQuery.sizeOf(context).height : 0) - fromSlide) * t;
      });
    }
    motion.addListener(tick);
    await motion.forward(from: 0);
    motion.removeListener(tick);
    if (mounted && dismiss) Navigator.of(context).pop();
  }
  @override void dispose() { motion.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Align(alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(heightFactor: fraction,
        child: Transform.translate(offset: Offset(0, slide),
        child: _GlassQueueSurface(primary: widget.primary, secondary: widget.secondary,
          child: Stack(children: [
            Positioned.fill(child: QueueListPanel(
              foregroundColor: widget.foreground,
              secondaryForegroundColor: widget.secondaryForeground)),
            Positioned(top: 0, left: 0, right: 0, height: 28,
              child: GestureDetector(behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  motion.stop(); drag = 0; startFraction = fraction;
                },
                onVerticalDragUpdate: (details) {
                  drag += details.delta.dy;
                  setState(() {
                    fraction = drag < 0
                        ? (startFraction - drag / bounds.maxHeight).clamp(.76, .96)
                        : startFraction;
                    slide = drag > 0 ? drag : 0;
                  });
                },
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (drag > 36 || velocity > 500) {
                    settle(startFraction, dismiss: true);
                  } else if (drag < -28 || velocity < -500) {
                    settle(.96);
                  } else {
                    settle(startFraction >= .86 ? .96 : .76);
                  }
                }, child: const SizedBox.expand())),
          ]))))));
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
        interactive: false,
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
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
            child: ReorderableListView.builder(
            physics: const ClampingScrollPhysics(),
            // Blur only beneath the dragged row, not its artwork/text.
            // Avoid the default opaque Material and animated elevation.
            proxyDecorator: (child, index, animation) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Material(
                  color: (foreground.computeLuminance() > .5
                      ? Colors.black : Colors.white).withValues(alpha: .28),
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  child: child,
                ),
              ),
            ),
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
        ),
      ],
    );
  }
}
