import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import 'liquid_surface.dart';

class KumoneGlassPlaylistDialog extends StatelessWidget {
  final Widget title, content;
  final List<Widget> actions;
  const KumoneGlassPlaylistDialog({super.key, required this.title,
    required this.content, required this.actions});
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    return Dialog(backgroundColor: Colors.transparent, elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        child: KumoneLiquidSurface(radius: 28, interactive: false,
          backingOpacity: settings.menuBackingOpacity, blur: settings.songMenuBlur,
          child: Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [DefaultTextStyle(style: Theme.of(context).textTheme.headlineSmall!, child: title),
                const SizedBox(height: 16), content, const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.end,
                  children: [for (final action in actions) Padding(padding: const EdgeInsets.only(left: 8), child: action)])])))));
  }
}
