import '../widgets/common.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class WallpaperCropPage extends StatefulWidget {
  final Uint8List bytes;
  final double aspectRatio;
  const WallpaperCropPage({super.key, required this.bytes, required this.aspectRatio});
  @override
  State<WallpaperCropPage> createState() => _WallpaperCropPageState();
}

class _WallpaperCropPageState extends State<WallpaperCropPage> {
  final _capture = GlobalKey();
  final _transform = TransformationController();
  bool _saving = false;
  Size? _imageSize;
  Size? _viewportSize;
  Matrix4 _initialTransform = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    _readImageSize();
  }

  Future<void> _readImageSize() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    if (mounted) setState(() => _imageSize = size);
  }

  @override
  void dispose() { _transform.dispose(); super.dispose(); }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final box = _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ratio = (2400 / box.size.longestSide).clamp(1.0, 4.0);
      final image = await box.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (mounted && data != null) Navigator.pop(context, data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF15171B),
    appBar: KumoneGlassAppBar(title: const SizedBox.shrink(),
      actions: [TextButton(onPressed: _saving ? null : _confirm,
        child: Text(_saving ? '保存中…' : '使用此裁切',
          style: const TextStyle(color: Colors.white)))]),
    body: SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.all(16),
        child: Text('双指缩放、拖动构图；框内就是保存后的背景。返回可取消。',
          style: TextStyle(color: Colors.white70))),
      Expanded(child: Padding(padding: const EdgeInsets.all(20),
        child: Center(child: AspectRatio(aspectRatio: widget.aspectRatio,
          child: DecoratedBox(decoration: BoxDecoration(
            border: Border.all(color: Colors.white54)),
            child: Padding(padding: const EdgeInsets.all(1),
              child: RepaintBoundary(key: _capture, child: ClipRect(
                child: LayoutBuilder(builder: (context, viewport) {
                  final imageSize = _imageSize;
                  if (imageSize == null) return const SizedBox.expand();
                  final scale = (viewport.maxWidth / imageSize.width) >
                      (viewport.maxHeight / imageSize.height)
                      ? viewport.maxWidth / imageSize.width
                      : viewport.maxHeight / imageSize.height;
                  final viewportSize = Size(viewport.maxWidth, viewport.maxHeight);
                  if (_viewportSize != viewportSize) {
                    _viewportSize = viewportSize;
                    _initialTransform = Matrix4.translationValues(
                      (viewport.maxWidth - imageSize.width * scale) / 2,
                      (viewport.maxHeight - imageSize.height * scale) / 2, 0);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _transform.value = _initialTransform.clone();
                    });
                  }
                  // Keep the entire cover-fitted image as the gesture child.
                  // BoxFit.cover in a viewport-sized child discards the overflow
                  // before InteractiveViewer can pan it.
                  return InteractiveViewer(
                    key: const ValueKey('wallpaper-crop-viewer'),
                    transformationController: _transform,
                    constrained: false, alignment: Alignment.topLeft,
                    minScale: 1, maxScale: 5,
                    child: SizedBox(width: imageSize.width * scale,
                      height: imageSize.height * scale,
                      child: Image.memory(widget.bytes, fit: BoxFit.fill,
                        gaplessPlayback: true)),
                  );
                }),
              )),
            ),
          ),
        )),
      )),
      TextButton(onPressed: () => _transform.value = _initialTransform.clone(),
        child: const Text('重置构图', style: TextStyle(color: Colors.white))),
    ])),
  );
}
