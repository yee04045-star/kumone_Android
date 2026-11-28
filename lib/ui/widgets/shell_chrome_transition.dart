import 'package:flutter/material.dart';

// Reveal live glass geometrically. An ancestor FadeTransition/Opacity creates
// an offscreen layer: refracting lenses read that empty layer until opacity=1,
// then suddenly acquire the real backdrop. ClipRect does not isolate backdrop
// sampling, so both the moving and settled frames use the same glass pipeline.
class KumoneShellChromeTransition extends StatefulWidget {
  final bool visible;
  final Widget child;
  const KumoneShellChromeTransition(
      {super.key, required this.visible, required this.child});

  @override
  State<KumoneShellChromeTransition> createState() =>
      _KumoneShellChromeTransitionState();
}

class _KumoneShellChromeTransitionState
    extends State<KumoneShellChromeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));
  late final Animation<double> _reveal =
      _controller.drive(CurveTween(curve: Curves.easeOutCubic));
  late final Animation<Offset> _position = _controller.drive(
      Tween<Offset>(begin: const Offset(0, .22), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic)));

  void _update() {
    if (!widget.visible) {
      _controller.value = 0;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(KumoneShellChromeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _update();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !widget.visible,
        child: ExcludeSemantics(
            excluding: !widget.visible,
            child: AnimatedBuilder(
              animation: _reveal,
              child: SlideTransition(position: _position, child: widget.child),
              builder: (_, child) => ClipRect(
                clipper: _ChromeRevealClipper(_reveal.value),
                child: child,
              ),
            )),
      );
}

class _ChromeRevealClipper extends CustomClipper<Rect> {
  final double progress;
  const _ChromeRevealClipper(this.progress);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, size.height * (1 - progress) - 32 * progress,
          size.width, size.height + 8 * progress);

  @override
  bool shouldReclip(_ChromeRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
