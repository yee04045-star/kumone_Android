import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TabHoldToTop extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final int itemCount;
  final VoidCallback onHold;
  const TabHoldToTop({super.key, required this.child, required this.selectedIndex,
    required this.itemCount, required this.onHold});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    int pressed = -1;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {LongPressGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 500)),
          (recognizer) {
            recognizer.onLongPressDown = (details) {
              // The bar is centered with a 14px inset at either side.
              final width = bounds.maxWidth - 28;
              pressed = ((details.localPosition.dx - 14) / (width / itemCount)).floor();
            };
            recognizer.onLongPress = () {
              if (pressed == selectedIndex) onHold();
            };
          })},
      child: child,
    );
  });
}

// Discover only live vertical scrollables on the top route. This also catches
// NestedScrollView's outer and inner positions without touching horizontal text.
void scrollVisibleRouteToTop(BuildContext? navigatorContext) {
  if (navigatorContext == null) return;
  final positions = <ScrollPosition>{};
  void visit(Element element) {
    if (element.widget is Offstage && (element.widget as Offstage).offstage) return;
    final route = ModalRoute.of(element);
    if (element is StatefulElement && element.state is ScrollableState &&
        route?.isCurrent == true &&
        !const ['/now-playing', '/settings', '/wallpaper-crop'].contains(route?.settings.name)) {
      final state = element.state as ScrollableState;
      final position = state.position;
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
