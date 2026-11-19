import 'dart:async';
import 'package:flutter/material.dart';

// Keeps artist/album links individually tappable while scrolling their row.
class AutoScrollMetadata extends StatefulWidget {
  final Widget child;
  final Object identity;
  const AutoScrollMetadata(
      {super.key, required this.child, required this.identity});
  @override
  State<AutoScrollMetadata> createState() => _AutoScrollMetadataState();
}

class _AutoScrollMetadataState extends State<AutoScrollMetadata> {
  final _scroll = ScrollController();
  Timer? _timer;
  int _epoch = 0;
  bool _enabled = false;
  void _start() {
    final epoch = ++_epoch;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || epoch != _epoch || !_scroll.hasClients || !_enabled) {
        return;
      }
      final distance = _scroll.position.maxScrollExtent;
      if (distance <= 1) return;
      await _scroll.animateTo(distance,
          duration: Duration(milliseconds: (distance / 28 * 1000).round()),
          curve: Curves.linear);
      if (!mounted || epoch != _epoch) return;
      _timer = Timer(const Duration(seconds: 2), () {
        if (!mounted || epoch != _epoch || !_scroll.hasClients) return;
        _scroll.jumpTo(0);
        _start();
      });
    });
  }

  @override
  void didUpdateWidget(covariant AutoScrollMetadata oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      ++_epoch;
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(0);
          if (_enabled) _start();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      _start();
    } else {
      ++_epoch;
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        return SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: widget.child,
          ),
        );
      });
  @override
  void dispose() {
    ++_epoch;
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }
}
