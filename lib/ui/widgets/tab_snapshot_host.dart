import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/wallpaper_store.dart';
import 'wallpaper_scope.dart';

/// Keeps tab states alive. Only tabs 1/2/3 are painted and captured in turn
/// once after startup. Subsequent departures use SnapshotWidget only.
class KumoneTabSnapshotHost extends StatefulWidget {
  final ValueListenable<int> selected;
  final List<Widget> pages;
  const KumoneTabSnapshotHost(
      {super.key, required this.selected, required this.pages});
  @override
  State<KumoneTabSnapshotHost> createState() => _KumoneTabSnapshotHostState();
}

class _KumoneTabSnapshotHostState extends State<KumoneTabSnapshotHost> {
  late final keys = List.generate(widget.pages.length, (_) => GlobalKey());
  final images = <int, ui.Image>{};
  Animation<double>? covered;
  int? coveredTab;
  late final controllers =
      List.generate(widget.pages.length, (_) => SnapshotController());
  final visited = <int>{0};
  int? warming;
  bool enabled = false;
  bool started = false;
  final startupClock = Stopwatch()..start();
  int epoch = 0;
  Object? environment;
  bool get frozen =>
      enabled &&
      covered?.status != AnimationStatus.dismissed &&
      covered != null;

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(select);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context)?.secondaryAnimation;
    if (next != covered) {
      covered?.removeStatusListener(coverChanged);
      covered = next;
      if (next != null && next.status != AnimationStatus.dismissed) {
        coveredTab = widget.selected.value;
      }
      covered?.addStatusListener(coverChanged);
    }
    final settings = context.watch<SettingsStore?>();
    final wallpaper = context.watch<WallpaperStore?>();
    enabled = settings?.freezeOutgoingPage ?? true;
    final signature = (
      MediaQuery.sizeOf(context),
      MediaQuery.devicePixelRatioOf(context),
      Theme.of(context),
      settings?.backgroundExtend,
      wallpaper?.path,
      wallpaper?.landscapePath,
      wallpaper?.blur,
    );
    if (signature != environment) {
      environment = signature;
      epoch++;
      for (final image in images.values) {
        image.dispose();
      }
      images.clear();
      // Invalidate startup images without repeating startup prewarming.
    }
    if (enabled && !started) {
      started = true;
      final token = epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) => warm(token));
    }
  }

  Future<void> warm(int token) async {
    for (final index in const [2, 1, 3]) {
      final due = index == 2 ? 240 : 2000;
      final wait = due - startupClock.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      // Stagger the two heavier pages rather than capturing both in one frame.
      if (index == 3) await Future<void>.delayed(const Duration(milliseconds: 240));
      if (!mounted || token != epoch || !enabled) return;
      // Never compete with a route transition. Defer until the root is visible.
      while (frozen && mounted && token == epoch) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!mounted || token != epoch) return;
      if (visited.contains(index)) continue;
      setState(() => warming = index);
      await WidgetsBinding.instance.endOfFrame;
      await capture(index, token);
      if (!mounted || token != epoch) return;
      setState(() => warming = null);
    }
  }

  Future<void> capture(int index, int token) async {
    if (!mounted || token != epoch || !enabled) return;
    final boundary = keys[index].currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        boundary.debugNeedsPaint ||
        !boundary.hasSize) {
      return;
    }
    try {
      final ratio = math.min(MediaQuery.devicePixelRatioOf(context),
          1600 / boundary.size.longestSide);
      final result = await boundary.toImage(pixelRatio: ratio);
      if (!mounted || token != epoch || !enabled || visited.contains(index)) {
        result.dispose();
        return;
      }
      setState(() {
        images.remove(index)?.dispose();
        images[index] = result;
      });
    } catch (_) {/* Use the live page if a texture cannot be captured. */}
  }

  void select() {
    if (!mounted) return;
    visited.add(widget.selected.value);
    if (!frozen) {
      images.remove(widget.selected.value)?.dispose();
    }
    setState(() {});
  }

  void coverChanged(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.forward && coveredTab == null) {
      coveredTab = widget.selected.value;
    }
    if (status == AnimationStatus.dismissed) {
      coveredTab = null;
      // The startup frame is a one-time bridge, never a permanent tab image.
      visited.add(widget.selected.value);
      images.remove(widget.selected.value)?.dispose();
    }
    setState(() {});
  }

  @override
  void dispose() {
    epoch++;
    for (final controller in controllers) {
      controller.dispose();
    }
    widget.selected.removeListener(select);
    covered?.removeStatusListener(coverChanged);
    for (final image in images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected.value;
    // A tab selected underneath an open detail is an incoming live page,
    // not the outgoing page that was visible when the detail was pushed.
    final freezeSelected = frozen && selected == coveredTab;
    final snapshot = freezeSelected ? images[selected] : null;
    for (var i = 0; i < controllers.length; i++) {
      controllers[i].allowSnapshotting =
          freezeSelected && i == selected && snapshot == null;
    }
    return Stack(fit: StackFit.expand, children: [
      for (final i in [
        for (var n = 0; n < widget.pages.length; n++)
          if (n != selected) n,
        selected
      ])
        Offstage(
            key: ValueKey(i),
            offstage: (i != selected && i != warming) ||
                (i == selected && snapshot != null),
            child: IgnorePointer(
                ignoring: i != selected || freezeSelected,
                child: TickerMode(
                    enabled: i == selected && !freezeSelected,
                    child: SnapshotWidget(
                        controller: controllers[i],
                        mode: SnapshotMode.permissive,
                        autoresize: true,
                        child: RepaintBoundary(
                            key: keys[i],
                            child: KumoneWallpaperRouteSurface(
                                child: widget.pages[i])))))),
      if (snapshot != null)
        Positioned.fill(
            child: IgnorePointer(
                child: RawImage(image: snapshot, fit: BoxFit.fill))),
    ]);
  }
}
