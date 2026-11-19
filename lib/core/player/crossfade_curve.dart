import 'dart:math' as math;

// Equal-power envelope, following miniaudio_player's MIT-licensed
// InternalCrossfadeController.computeVolumes. See THIRD_PARTY_NOTICES.md and third_party/licenses/MINIAUDIO_PLAYER_MIT.txt.
(double, double) crossfadeGains(double progress, double volume) {
  final angle = progress.clamp(0.0, 1.0) * math.pi / 2;
  return (math.cos(angle) * volume, math.sin(angle) * volume);
}
