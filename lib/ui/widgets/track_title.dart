import 'content_fade.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';

class KumoneTrackTitle extends StatelessWidget {
  final int trackId;
  final String title;
  final int? maxLines;
  final TextOverflow? overflow;
  const KumoneTrackTitle({super.key, required this.trackId, required this.title,
    this.maxLines, this.overflow});

  @override
  Widget build(BuildContext context) {
    final active = context.select<PlayerController, bool>(
      (player) => player.isCurrentTrack(trackId));
    return KumoneLoadingText(title, maxLines: maxLines, overflow: overflow,
      style: active ? TextStyle(color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700) : null);
  }
}

class KumoneTrackTrailing extends StatelessWidget {
  final String album;
  final Widget duration;
  const KumoneTrackTrailing({super.key, required this.album, required this.duration});
  @override Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 700) return duration;
    return SizedBox(width: (width * .32).clamp(180.0, 420.0),
      child: Row(children: [Expanded(child: Text(album, maxLines: 1,
        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(width: 24), duration]));
  }
}
