import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// Observe only events delivered by Android; never place a hit-test overlay
// above the OS status bar or request accessibility/overlay permissions.
class StatusBarScrollTop extends StatefulWidget {
  final bool enabled;
  final VoidCallback onDoubleTap;
  final Widget child;
  const StatusBarScrollTop({super.key, required this.enabled,
    required this.onDoubleTap, required this.child});
  @override State<StatusBarScrollTop> createState() => _StatusBarScrollTopState();
}
class _StatusBarScrollTopState extends State<StatusBarScrollTop> {
  Offset? down, lastTap;
  Duration? downTime, lastTime;
  int? pointer;
  @override void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(event);
  }
  void event(PointerEvent event) {
    if (!mounted || !widget.enabled) { reset(); return; }
    final top = MediaQuery.viewPaddingOf(context).top;
    if (event is PointerDownEvent) {
      if (event.position.dy < 0 || event.position.dy >= top || pointer != null) {
        reset(); return;
      }
      pointer = event.pointer; down = event.position; downTime = event.timeStamp;
    } else if (event.pointer == pointer && event is PointerMoveEvent) {
      if ((event.position - down!).distance > 18) reset();
    } else if (event.pointer == pointer && event is PointerUpEvent) {
      final valid = down != null && (event.position - down!).distance <= 18 &&
        event.timeStamp - downTime! < const Duration(milliseconds: 250);
      pointer = null; down = null;
      if (!valid) { reset(); return; }
      if (lastTime != null && event.timeStamp - lastTime! <= const Duration(milliseconds: 350) &&
          (event.position - lastTap!).distance <= 40) {
        reset(); widget.onDoubleTap();
      } else { lastTime = event.timeStamp; lastTap = event.position; }
    } else if (event is PointerCancelEvent) { reset(); }
  }
  void reset() { pointer = null; down = null; downTime = null; lastTap = null; lastTime = null; }
  @override void didUpdateWidget(StatusBarScrollTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) reset();
  }
  @override Widget build(BuildContext context) => widget.child;
  @override void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(event);
    super.dispose();
  }
}

void scrollVisibleRouteToTop(BuildContext? navigatorContext) {
  if (navigatorContext == null) return;
  final positions = <ScrollPosition>{};
  void visit(Element element) {
    if (element.widget is Offstage && (element.widget as Offstage).offstage) return;
    final route = ModalRoute.of(element);
    if (element is StatefulElement && element.state is ScrollableState &&
        route is PageRoute && route.isCurrent &&
        !const ['/now-playing', '/wallpaper-crop'].contains(route.settings.name)) {
      final position = (element.state as ScrollableState).position;
      if (axisDirectionToAxis(position.axisDirection) == Axis.vertical &&
          position.hasContentDimensions && position.pixels > position.minScrollExtent) {
        positions.add(position);
      }
    }
    element.visitChildren(visit);
  }
  (navigatorContext as Element).visitChildren(visit);
  for (final position in positions) {
    position.animateTo(position.minScrollExtent,
      duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }
}
