import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Cache only the wallpaper, never the content or its interactive glass.
class CachedWallpaper extends StatefulWidget {
  static bool cacheEnabled = true;
  final String path;
  final double sigma;
  const CachedWallpaper({super.key, required this.path, required this.sigma});
  @visibleForTesting
  static Future<ui.Image> renderForTest(String path, int width, int height, double sigma) =>
      _CachedWallpaperState.render(path, width, height, sigma, 1);

  static Future<void> settlePending() async {
    await Future.wait(_CachedWallpaperState._pending.values.map((job) async {
      try { await job; } catch (_) {}
    }));
  }

  @override
  State<CachedWallpaper> createState() => _CachedWallpaperState();
}

class _CachedWallpaperState extends State<CachedWallpaper> {
  static final _cache = <String, ui.Image>{};
  static final _pending = <String, Future<ui.Image>>{};
  ui.Image? image;
  String? requested;
  int generation = 0;

  static Future<ui.Image> render(
      String path, int width, int height, double sigma, double ratio) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(),
        targetWidth: width, allowUpscaling: false);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final source = frame.image;
    final fitted = applyBoxFit(
        BoxFit.cover,
        Size(source.width.toDouble(), source.height.toDouble()),
        Size(width.toDouble(), height.toDouble()));
    final src = Alignment.center.inscribe(fitted.source,
        Offset.zero & Size(source.width.toDouble(), source.height.toDouble()));
    final dst = Offset.zero & Size(width.toDouble(), height.toDouble());
    canvas.drawImageRect(
        source,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma * ratio,
              sigmaY: sigma * ratio,
              tileMode: TileMode.clamp));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
      source.dispose();
    }
  }

  void request(Size size, double dpr) {
    final ratio = math.min(dpr, 2048 / size.longestSide);
    final width = math.max(1, (size.width * ratio).round());
    final height = math.max(1, (size.height * ratio).round());
    final key = '${widget.path}|$width|$height|${widget.sigma}';
    if (requested == key) return;
    requested = key;
    final token = ++generation;
    () async {
      try {
        var cached = _cache[key];
        if (cached == null) {
          final job = _pending.putIfAbsent(key,
              () => render(widget.path, width, height, widget.sigma, ratio));
          final result = await job;
          cached = _cache[key];
          if (cached == null) {
            cached = result;
            _cache[key] = result;
            while (_cache.length > 3) {
              _cache.remove(_cache.keys.first)!.dispose();
            }
          }
          _pending.remove(key);
        }
        if (!mounted || token != generation) return;
        final next = cached.clone();
        setState(() {
          image?.dispose();
          image = next;
        });
      } catch (_) {
        _pending.remove(key);
      }
    }();
  }

  @override
  void dispose() {
    generation++;
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && CachedWallpaper.cacheEnabled) request(size, MediaQuery.devicePixelRatioOf(context));
        });
        if (image != null) return RawImage(image: image, fit: BoxFit.fill);
        return ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: widget.sigma,
                sigmaY: widget.sigma,
                tileMode: TileMode.clamp),
            child: Image.file(File(widget.path),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.expand()));
      });
}
