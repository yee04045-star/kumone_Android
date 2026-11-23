import 'package:flutter/material.dart';

// Use only on ordinary content, never around backdrop-filter/glass containers.
class KumoneContentFade extends StatefulWidget {
  final Widget child;
  const KumoneContentFade({super.key, required this.child});
  @override
  State<KumoneContentFade> createState() => _ContentFadeState();
}

class _ContentFadeState extends State<KumoneContentFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 320))..forward();
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: controller, child: widget.child);
  @override
  void dispose() { controller.dispose(); super.dispose(); }
}

class KumoneLoadingText extends Text {
  const KumoneLoadingText(super.data, {super.key, super.style, super.strutStyle,
    super.textAlign, super.textDirection, super.locale, super.softWrap,
    super.overflow, super.textScaler, super.maxLines, super.semanticsLabel,
    super.textWidthBasis, super.textHeightBehavior, super.selectionColor});
  @override
  Widget build(BuildContext context) => KumoneContentFade(child: super.build(context));
}
