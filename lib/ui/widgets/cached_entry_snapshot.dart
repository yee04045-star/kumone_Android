import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../core/storage/wallpaper_store.dart';
import 'wallpaper_scope.dart';

// Only the explicitly cached detail families use this first-screen bridge.
class CachedEntrySnapshot extends StatefulWidget {
  final String identity;
  final String family;
  final bool ready;
  final Widget child;
  const CachedEntrySnapshot({super.key, required this.identity,
    required this.family, required this.ready, required this.child});
  @override State<CachedEntrySnapshot> createState() => _EntrySnapshotState();
}
class _EntrySnapshotState extends State<CachedEntrySnapshot>
    with SingleTickerProviderStateMixin {
  static final images = <String, ({String identity, Object environment, ui.Image image})>{};
  final boundary = GlobalKey();
  late final fade = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 240), value: 1);
  Animation<double>? animation;
  ui.Image? incoming;
  Object? environment;
  Timer? captureTimer;
  bool scheduled = false, scrolled = false, revealing = false;
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final wallpaper = context.watch<WallpaperStore?>();
    environment = (MediaQuery.sizeOf(context), MediaQuery.devicePixelRatioOf(context),
      Theme.of(context), wallpaper?.path, wallpaper?.landscapePath, wallpaper?.blur);
    final next = ModalRoute.of(context)?.animation;
    if (animation != next) {
      animation?.removeStatusListener(changed);
      animation = next;
      animation?.addStatusListener(changed);
      final cached = images[widget.family];
      if (widget.ready && cached?.identity == widget.identity && cached?.environment == environment) {
        incoming = cached!.image.clone();
      }
    }
    scheduleCapture();
    if (animation == null || animation!.status == AnimationStatus.completed) reveal();
  }
  @override void didUpdateWidget(CachedEntrySnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    scheduleCapture();
  }
  void scheduleCapture() {
    if (!widget.ready || scheduled || incoming != null) return;
    scheduled = true;
    // Let initial content fades settle, but never capture after the user scrolls.
    captureTimer = Timer(const Duration(milliseconds: 900), capture);
  }
  void changed(AnimationStatus status) {
    if (status == AnimationStatus.completed) reveal();
  }
  Future<void> reveal() async {
    if (incoming == null || revealing || !mounted) return;
    setState(() => revealing = true);
    // Paint the live surface underneath before fading only the bitmap overlay.
    await WidgetsBinding.instance.endOfFrame;
    // Content-level entry fades restart when the offstage tree is revealed.
    // Keep the bitmap opaque until those finish, then cross to the live frame.
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    await fade.reverse();
    if (!mounted) return;
    setState(() { incoming?.dispose(); incoming = null; });
  }
  Future<void> capture() async {
    if (!mounted || scrolled || !widget.ready ||
        animation?.status == AnimationStatus.reverse) {
      return;
    }
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary || render.debugNeedsPaint || !render.hasSize) return;
    final identity = widget.identity;
    final signature = environment!;
    try {
      final image = await render.toImage(pixelRatio:
        (1400 / render.size.longestSide).clamp(.1, MediaQuery.devicePixelRatioOf(context)));
      if (!mounted || scrolled || identity != widget.identity || signature != environment) {
        image.dispose(); return;
      }
      images.remove(widget.family)?.image.dispose();
      images[widget.family] = (identity: identity, environment: signature, image: image);
    } catch (_) { /* Fall back to live content if capture is unavailable. */ }
  }
  @override Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    Offstage(offstage: incoming != null && !revealing,
      child: TickerMode(enabled: incoming == null || revealing,
        child: NotificationListener<ScrollNotification>(onNotification: (event) {
          if (event.metrics.pixels.abs() > 1) scrolled = true;
          return false;
        }, child: RepaintBoundary(key: boundary,
          child: KumoneWallpaperRouteSurface(child: widget.child))))),
    if (incoming != null) Positioned.fill(child: IgnorePointer(
      child: FadeTransition(opacity: fade, child: RawImage(image: incoming, fit: BoxFit.fill)))),
  ]);
  @override void dispose() {
    captureTimer?.cancel();
    animation?.removeStatusListener(changed);
    fade.dispose();
    incoming?.dispose();
    super.dispose();
  }
}
