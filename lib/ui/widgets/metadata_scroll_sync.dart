import 'dart:math' as math;
import 'package:flutter/material.dart';

class MetadataScrollTiming extends ChangeNotifier {
  final distances = <String, double>{};
  double get distance => distances.values.fold(0, math.max);
  void report(String key, double value) {
    if (distances[key] == value) return;
    distances[key] = value;
    notifyListeners();
  }
}
class MetadataScrollSync extends StatefulWidget {
  final Widget child;
  const MetadataScrollSync({super.key, required this.child});
  static MetadataScrollTiming? of(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_TimingScope>()?.notifier;
  @override State<MetadataScrollSync> createState() => _SyncState();
}
class _SyncState extends State<MetadataScrollSync> {
  final timing = MetadataScrollTiming();
  @override Widget build(BuildContext context) => _TimingScope(notifier: timing, child: widget.child);
  @override void dispose() { timing.dispose(); super.dispose(); }
}
class _TimingScope extends InheritedNotifier<MetadataScrollTiming> {
  const _TimingScope({required super.notifier, required super.child});
}
