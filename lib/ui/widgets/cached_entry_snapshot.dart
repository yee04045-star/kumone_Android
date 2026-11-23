import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'wallpaper_scope.dart';
import 'package:provider/provider.dart';
import '../../core/storage/wallpaper_store.dart';

// Only the three explicitly cached detail families use this bridge.
class CachedEntrySnapshot extends StatefulWidget {
  final String identity;
  final String family;
  final bool ready;
  final Widget child;
  const CachedEntrySnapshot({super.key, required this.identity,
    required this.family, required this.ready, required this.child});
  @override State<CachedEntrySnapshot> createState() => _EntrySnapshotState();
}
class _EntrySnapshotState extends State<CachedEntrySnapshot> {
  static final images = <String, ({String identity, Object environment, ui.Image image})>{};
  final boundary = GlobalKey();
  Animation<double>? animation;
  ui.Image? incoming;
  Object? environment;
  bool capturing = false;
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final wallpaper = context.watch<WallpaperStore?>();
    final signature = (MediaQuery.sizeOf(context), MediaQuery.devicePixelRatioOf(context),
      Theme.of(context), wallpaper?.path, wallpaper?.landscapePath, wallpaper?.blur);
    environment = signature;
    final next = ModalRoute.of(context)?.animation;
    if (animation != next) {
      animation?.removeStatusListener(changed);
      animation = next;
      animation?.addStatusListener(changed);
      final cached = images[widget.family];
      if (widget.ready && cached?.identity == widget.identity && cached?.environment == signature) {
        incoming = cached!.image.clone();
      }
    }
  }
  void changed(AnimationStatus status) {
    if (status == AnimationStatus.reverse && widget.ready) capture();
    if (status == AnimationStatus.completed && mounted) {
      setState(() { incoming?.dispose(); incoming = null; });
    }
  }
  Future<void> capture() async {
    if (capturing) return;
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary || render.debugNeedsPaint || !render.hasSize) return;
    capturing = true;
    final identity = widget.identity;
    final signature = environment!;
    try {
      final image = await render.toImage(pixelRatio:
        (1400 / render.size.longestSide).clamp(.1, MediaQuery.devicePixelRatioOf(context)));
      if (!mounted) { image.dispose(); return; }
      images.remove(widget.family)?.image.dispose();
      images[widget.family] = (identity: identity, environment: signature, image: image);
    } catch (_) { /* A failed capture falls back to live content. */ }
    capturing = false;
  }
  @override Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    Offstage(offstage: incoming != null,
      child: TickerMode(enabled: incoming == null,
        child: RepaintBoundary(key: boundary,
          child: KumoneWallpaperRouteSurface(child: widget.child)))),
    if (incoming != null) RawImage(image: incoming, fit: BoxFit.fill),
  ]);
  @override void dispose() {
    animation?.removeStatusListener(changed);
    incoming?.dispose();
    super.dispose();
  }
}
