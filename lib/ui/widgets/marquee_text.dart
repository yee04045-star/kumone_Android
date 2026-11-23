import 'dart:async';
import 'scroll_text_edges.dart';
import 'package:flutter/material.dart';

// Single copy, edge-clipped marquee. No animation/timer when the text fits.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final double pixelsPerSecond;
  final bool scrollEnabled;
  final Duration startPause;
  const MarqueeText(this.text,
      {super.key, this.style, this.textAlign = TextAlign.start, this.pixelsPerSecond = 28,
      this.scrollEnabled = true, this.startPause = const Duration(seconds: 3)});
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Timer? _pause;
  double _distance = 0;
  String _signature = '';
  int _generation = 0;

  void _configure(String signature, double distance) {
    if (_signature == signature) return;
    _signature = signature;
    final generation = ++_generation;
    _pause?.cancel();
    _controller.stop();
    _controller.value = 0;
    _distance = distance;
    if (distance <= 0) return;
    void cycle() {
      _pause = Timer(widget.startPause, () async {
        if (!mounted || generation != _generation) return;
        _controller.duration =
            Duration(milliseconds: (distance / widget.pixelsPerSecond * 1000).round());
        await _controller.forward(from: 0).orCancel.catchError((Object _) {});
        if (!mounted || generation != _generation) return;
        _pause = Timer(const Duration(seconds: 2), () async {
          if (!mounted || generation != _generation) return;
          await _controller.reverse(from: 1).orCancel.catchError((Object _) {});
          if (!mounted || generation != _generation) return;
          cycle();
        });
      });
    }

    cycle();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style.merge(widget.style);
        final direction = Directionality.of(context);
        final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            textDirection: direction,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1)
          ..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final reduce = !widget.scrollEnabled || MediaQuery.disableAnimationsOf(context) ||
            !TickerMode.valuesOf(context).enabled;
        final distance = constraints.hasBoundedWidth && !reduce
            ? (width - constraints.maxWidth).clamp(0.0, double.infinity)
            : 0.0;
        // Configure after layout, without marking widgets dirty during build.
        final signature =
            '${widget.text}|$style|${constraints.maxWidth}|$reduce|$direction';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _configure(signature, distance);
        });
        if (distance <= 0) {
          return SizedBox(width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
            child: Text(widget.text, style: style, maxLines: 1,
              overflow: TextOverflow.ellipsis, textAlign: widget.textAlign));
        }
        return Semantics(
            label: widget.text,
            child: ExcludeSemantics(
                child: ClipRect(
              child: SizedBox(
                  height: height,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => ScrollTextEdges(
                      left: (_distance * _controller.value / 14).clamp(0.0, 1.0),
                      right: (_distance * (1 - _controller.value) / 14).clamp(0.0, 1.0),
                      child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width,
                      maxWidth: width,
                      child: Transform.translate(
                          offset: Offset(-_distance * _controller.value, 0),
                          child: Text(widget.text,
                              style: style, maxLines: 1, softWrap: false)),
                    )), 
                  )),
            )));
      });
  @override
  void dispose() {
    ++_generation;
    _pause?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
