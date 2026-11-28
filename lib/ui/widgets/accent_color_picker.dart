import 'package:flutter/material.dart';

class AccentColorPicker extends StatefulWidget {
  final Color initial;
  const AccentColorPicker({super.key, required this.initial});
  @override State<AccentColorPicker> createState() => _PickerState();
}
class _PickerState extends State<AccentColorPicker> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  String? hexError;
  late final hex = TextEditingController(text: '#${(widget.initial.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}');
  void syncHex() { hex.text = '#${(hsv.toColor().toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}'; hexError = null; }
  @override void dispose() { hex.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义主题色'),
    content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [
      LayoutBuilder(builder: (context, bounds) {
        void select(Offset position) => setState(() { hsv = hsv
          .withSaturation((position.dx / bounds.maxWidth).clamp(0, 1))
          .withValue((1 - position.dy / 180).clamp(0, 1)); syncHex(); });
        return GestureDetector(onTapDown: (e) => select(e.localPosition),
          onPanStart: (e) => select(e.localPosition), onPanUpdate: (e) => select(e.localPosition),
          child: SizedBox(height: 180, child: Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()])))),
            const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black])))),
            Positioned(left: (hsv.saturation * bounds.maxWidth - 6).clamp(0, bounds.maxWidth - 12),
              top: ((1 - hsv.value) * 180 - 6).clamp(0, 168),
              child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2), color: hsv.toColor()))),
          ])));
      }),
      const SizedBox(height: 12),
      Semantics(label: '色相', child: Slider(value: hsv.hue, min: 0, max: 360,
        onChanged: (value) => setState(() { hsv = hsv.withHue(value); syncHex(); }))),
      Row(children: [Container(width: 32, height: 32, decoration: BoxDecoration(
        color: hsv.toColor(), shape: BoxShape.circle)), const SizedBox(width: 12),
        Expanded(child: TextField(controller: hex,
          decoration: InputDecoration(labelText: 'HEX 色号', hintText: '#DD3A3F', errorText: hexError),
          onChanged: (value) => setState(() {
            final text = value.trim().replaceFirst(RegExp(r'^#'), '');
            if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) { hexError = '请输入六位色号'; return; }
            hexError = null;
            hsv = HSVColor.fromColor(Color(0xff000000 | int.parse(text, radix: 16)));
          })))]),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      TextButton(onPressed: hexError != null ? null : () => Navigator.pop(context, hsv.toColor()), child: const Text('使用此颜色'))],
  );
}
