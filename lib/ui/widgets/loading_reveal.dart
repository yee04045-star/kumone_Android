import 'dart:async';
import 'package:flutter/material.dart';
import 'loading_placeholder.dart';

class KumoneLoadingReveal extends StatefulWidget {
  final Widget child;
  const KumoneLoadingReveal({super.key, required this.child});
  @override State<KumoneLoadingReveal> createState() => _LoadingRevealState();
}
class _LoadingRevealState extends State<KumoneLoadingReveal> {
  Timer? timer;
  bool ready = false;
  @override void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => ready = true);
    });
  }
  @override Widget build(BuildContext context) => ready ? widget.child
      : const KumoneLoadingPlaceholder();
  @override void dispose() { timer?.cancel(); super.dispose(); }
}
