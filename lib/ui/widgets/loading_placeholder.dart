import 'package:flutter/material.dart';

/// Static placeholders; no timers or refresh spinners.
class KumoneLoadingPlaceholder extends StatelessWidget {
  final bool grid;
  final bool circle;
  final bool header;
  const KumoneLoadingPlaceholder({super.key, this.grid = false,
    this.circle = false, this.header = false});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget box(double h, {double? w, double radius = 8}) => Container(
      height: h, width: w, decoration: BoxDecoration(color: color,
        borderRadius: BorderRadius.circular(radius)));
    if (grid) { return GridView.builder(physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190,
        crossAxisSpacing: 14, mainAxisSpacing: 18,
        mainAxisExtent: circle ? 166 : null, childAspectRatio: .74),
      itemCount: 8, itemBuilder: (_, i) => Column(children: [
        if (circle) box(128, w: 128, radius: 64)
        else AspectRatio(aspectRatio: 1, child: box(128, radius: 14)),
        const SizedBox(height: 8), box(14),
      ])); }
    return ListView(physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20), children: [
        if (header) ...[
          Row(children: [box(112, w: 112, radius: circle ? 56 : 14),
            const SizedBox(width: 18), Expanded(child: Column(children: [
              box(20), const SizedBox(height: 8), box(14),
              const SizedBox(height: 16), box(40, radius: 20)]))]),
          const SizedBox(height: 20),
        ],
        for (var i = 0; i < 10; i++) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [box(52, w: 52, radius: 9), const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [box(16), const SizedBox(height: 8), box(12, w: 120)])),
            const SizedBox(width: 16), box(12, w: 28)])),
      ]);
  }
}
