import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'liquid_surface.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';

class GlassCategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool menuOptics;
  final double height;
  const GlassCategoryChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap,
      this.menuOptics = false,
      this.height = 38});

  @override
  Widget build(BuildContext context) {
    final settings = menuOptics ? context.watch<SettingsStore>() : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedScale(
        scale: selected ? 1.025 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        child: KumoneLiquidSurface(
          radius: 20,
          blur: settings?.songMenuBlur ?? (selected ? 8 : 16),
          backingOpacity: settings?.menuBackingOpacity ??
              (selected ? (dark ? .55 : .78) : (dark ? .18 : .24)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: selected
                          ? (dark
                              ? Colors.white38
                              : Colors.white.withValues(alpha: .9))
                          : Colors.transparent),
                ),
                alignment: Alignment.center,
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                        color: foreground))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'Neutral glass categories', size: Size(360, 70))
Widget categoryChipsPreview() => MaterialApp(
        home: Scaffold(
            body: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        GlassCategoryChip(label: '全部', selected: true, onTap: () {}),
        GlassCategoryChip(label: '推荐歌单', selected: false, onTap: () {})
      ],
    )));
