import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import '../theme/app_theme.dart';

class OriginalPlayerTheme extends StatelessWidget {
  final Widget child;
  const OriginalPlayerTheme({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final appearance = settings.appearance;
    final dark = appearance == AppearanceMode.dark ||
        (appearance == AppearanceMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Theme(
        data: dark ? KumoneTheme.dark(color: settings.accent.color)
            : KumoneTheme.light(color: settings.accent.color), child: child);
  }
}
