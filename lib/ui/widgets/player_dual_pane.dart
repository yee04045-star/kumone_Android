import 'dart:math' as math;
import 'package:flutter/material.dart';

class KumonePlayerDualPane extends StatelessWidget {
  final Widget Function(double coverSize, bool spacious) playerBuilder;
  final Widget lyrics;
  const KumonePlayerDualPane(
      {super.key, required this.playerBuilder, required this.lyrics});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final spacious = box.maxHeight >= 560;
        final margin = (box.maxWidth * .025).clamp(12.0, 40.0);
        final gap = (box.maxWidth * .035).clamp(20.0, 64.0);
        final contentWidth = box.maxWidth - margin * 2 - gap;
        final leftWidth = math.min(520.0, contentWidth * .43);
        // Reserve metadata, timeline and transport before allocating the cover.
        final reserved = spacious ? 340.0 : 188.0;
        final cover =
            math.min(leftWidth * .80, math.max(64.0, box.maxHeight - reserved));
        return Padding(
          padding: EdgeInsets.fromLTRB(margin, 4, margin, 12),
          child: Row(children: [
            SizedBox(
                width: leftWidth,
                child: LayoutBuilder(
                    builder: (context, pane) => SingleChildScrollView(
                            child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: pane.maxHeight),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [playerBuilder(cover, spacious)]),
                        )))),
            SizedBox(width: gap),
            Expanded(child: lyrics),
          ]),
        );
      });
}
