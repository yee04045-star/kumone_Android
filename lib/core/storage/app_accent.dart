import 'dart:ui';

enum AppAccent {
  appleBlue('Apple 蓝', Color(0xFF0A84FF)),
  appleRed('Apple 红', Color(0xFFDD3A3F)),
  neteaseRed('网易云红', Color(0xFFC3473B)),
  spotifyGreen('Spotify 绿', Color(0xFF65D46E)),
  qqGreen('QQ 音乐绿', Color(0xFF31C27C));

  const AppAccent(this.label, this.color);
  final String label;
  final Color color;
}
