import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'liquid_surface.dart';

@Preview(name: 'Glass controls', size: Size(380, 220))
Widget glassControlsPreview() => MaterialApp(
        home: Scaffold(
            body: Column(children: [
      KumoneGlassSwitchTile(
          value: true, title: const Text('液态玻璃'), onChanged: (_) {}),
      KumoneGlassSlider(value: .5, onChanged: (_) {}),
      const Padding(
          padding: EdgeInsets.all(16),
          child: KumoneGlassSearchField(
              decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: '搜索此歌单'))),
    ])));

class KumoneGlassSwitchTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title, subtitle, secondary;
  const KumoneGlassSwitchTile(
      {super.key,
      required this.value,
      required this.onChanged,
      this.title,
      this.subtitle,
      this.secondary});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: secondary,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: SizedBox(
            width: 60,
            height: 42,
            child: LiquidGlassSwitch(
                value: value,
                onChanged: onChanged ?? (_) {},
                activeColor: Theme.of(context).colorScheme.primary)),
      );
}

class KumoneGlassSlider extends StatelessWidget {
  final double value, min, max;
  final String? label;
  final bool compact;
  final Color? activeColor;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  const KumoneGlassSlider(
      {super.key,
      required this.value,
      this.min = 0,
      this.max = 1,
      this.label,
      this.compact = false,
      this.activeColor,
      required this.onChanged,
      this.onChangeStart,
      this.onChangeEnd});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 20),
        child: SizedBox(
            height: compact ? 30 : 48,
            child: LiquidGlassSlider(
                value: value.clamp(min, max),
                minimumValue: min,
                maximumValue: max,
                onChanged: onChanged ?? (_) {},
                onChangeStart: onChangeStart,
                onChangeEnd: onChangeEnd,
                activeColor:
                    activeColor ?? Theme.of(context).colorScheme.primary)),
      );
}

class KumoneGlassIconButton extends StatelessWidget {
  final String? tooltip;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final Widget icon;
  const KumoneGlassIconButton(
      {super.key,
      this.tooltip,
      required this.onPressed,
      this.style,
      required this.icon});
  @override
  Widget build(BuildContext context) => KumoneLiquidSurface(
      radius: 24,
      backingOpacity: context.watch<SettingsStore?>()?.menuBackingOpacity ?? .20,
      blur: context.watch<SettingsStore?>()?.songMenuBlur ?? 14,
      child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: style?.copyWith(
              backgroundColor:
                  const WidgetStatePropertyAll(Colors.transparent)),
          icon: icon));
}

class KumoneGlassSearchField extends StatelessWidget {
  final ValueChanged<String>? onChanged;
  final InputDecoration? decoration;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final double height;
  const KumoneGlassSearchField({super.key, this.onChanged, this.decoration,
    this.controller, this.onSubmitted, this.height = 40});
  @override
  Widget build(BuildContext context) => KumoneLiquidSurface(
      radius: 26,
      backingOpacity: context.watch<SettingsStore?>()?.menuBackingOpacity ?? .20,
      blur: context.watch<SettingsStore?>()?.songMenuBlur ?? 14,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SizedBox(height: height, child: TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, height: 1.2),
          maxLines: 1,
          textAlignVertical: TextAlignVertical.center,
          decoration: (decoration ?? const InputDecoration()).copyWith(
              isDense: true,
              constraints: BoxConstraints.tightFor(height: height),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              prefixIcon: decoration?.prefixIcon == null ? null : SizedBox(
                width: height, height: height,
                child: Center(child: IconTheme.merge(
                  data: const IconThemeData(size: 20),
                  child: Transform.translate(offset: const Offset(0, 1),
                    child: decoration!.prefixIcon!)))),
              prefixIconConstraints:
                  BoxConstraints.tightFor(width: height, height: height),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none))));
}
