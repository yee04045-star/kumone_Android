import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// Native iOS pull/armed/release state machine, deliberately without a spinner.
// Keep the public name so all existing refresh pages share the same behaviour.
class KumoneGlassRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final double displacement;
  final double edgeOffset;

  const KumoneGlassRefresh(
      {super.key,
      required this.onRefresh,
      required this.child,
      this.displacement = 40,
      this.edgeOffset = 0});
  const KumoneGlassRefresh.adaptive(
      {super.key,
      required this.onRefresh,
      required this.child,
      this.displacement = 40,
      this.edgeOffset = 0});

  @override
  Widget build(BuildContext context) {
    final scroll = child;
    if (scroll is ScrollView &&
        scroll.scrollDirection == Axis.vertical &&
        !scroll.reverse &&
        !scroll.shrinkWrap &&
        (scroll is CustomScrollView || scroll is ListView)) {
      final List<Widget> slivers;
      if (scroll is CustomScrollView) {
        slivers = scroll.slivers;
      } else {
        final list = scroll as ListView;
        slivers = [
          SliverPadding(
            padding: list.padding ??
                MediaQuery.paddingOf(context).copyWith(left: 0, right: 0),
            sliver: SliverList(delegate: list.childrenDelegate),
          )
        ];
      }
      return CustomScrollView(
        key: scroll.key,
        controller: scroll.controller,
        primary: scroll.primary,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: scroll.keyboardDismissBehavior,
        restorationId: scroll.restorationId,
        clipBehavior: scroll.clipBehavior,
        slivers: [
          CupertinoSliverRefreshControl(
            refreshTriggerPullDistance: 100,
            refreshIndicatorExtent: 0,
            onRefresh: onRefresh,
            builder: (_, __, ___, ____, _____) => const SizedBox.shrink(),
          ),
          ...slivers,
        ],
      );
    }
    // Non-sliver callers retain Flutter's guarded release-to-refresh logic.
    return RefreshIndicator.noSpinner(onRefresh: onRefresh, child: child);
  }
}
