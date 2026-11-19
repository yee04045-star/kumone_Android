import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';

class KumoneSnapshotPageRoute<T> extends CupertinoPageRoute<T> {
  KumoneSnapshotPageRoute({required super.builder});
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) =>
    super.buildTransitions(context, animation, secondaryAnimation,
      KumoneRouteSnapshot(covered: secondaryAnimation, child: child));
}

class KumoneRouteSnapshot extends StatefulWidget {
  final Animation<double> covered;
  final Widget child;
  const KumoneRouteSnapshot(
      {super.key, required this.covered, required this.child});
  @override
  State<KumoneRouteSnapshot> createState() => _KumoneRouteSnapshotState();
}

class _KumoneRouteSnapshotState extends State<KumoneRouteSnapshot> {
  final controller = SnapshotController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        context.watch<SettingsStore?>()?.freezeOutgoingPage ?? false;
    return AnimatedBuilder(
        animation: widget.covered,
        child: widget.child,
        builder: (context, child) {
          final freeze =
              enabled && widget.covered.status != AnimationStatus.dismissed;
          controller.allowSnapshotting = freeze;
          return TickerMode(
              enabled: !freeze,
              child: SnapshotWidget(
                  controller: controller,
                  mode: SnapshotMode.permissive,
                  autoresize: true,
                  child: child!));
        });
  }
}
