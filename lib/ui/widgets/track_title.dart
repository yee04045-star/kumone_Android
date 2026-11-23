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
      (player) => player.currentTrack?.id == trackId);
    return KumoneLoadingText(title, maxLines: maxLines, overflow: overflow,
      style: active ? TextStyle(color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700) : null);
  }
}
