import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import 'liquid_surface.dart';

class KumoneSourceNotice extends StatefulWidget {
  final String? message;
  const KumoneSourceNotice({super.key, this.message});
  @override State<KumoneSourceNotice> createState() => _NoticeState();
}
class _NoticeState extends State<KumoneSourceNotice> with SingleTickerProviderStateMixin {
  late final fade = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 240), value: widget.message == null ? 0 : 1);
  final snapshot = SnapshotController();
  String? text;
  bool frozen = false;
  @override void initState() { super.initState(); text = widget.message; }
  @override void didUpdateWidget(KumoneSourceNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message == oldWidget.message) return;
    if (widget.message != null) {
      frozen = false; snapshot.allowSnapshotting = false;
      text = widget.message; fade.value = 1;
    } else {
      // Freeze only for exit: fade a bitmap rather than a live glass layer.
      frozen = true; snapshot.allowSnapshotting = true;
      fade.reverse().then((_) {
        if (mounted && widget.message == null) setState(() => text = null);
      });
    }
  }
  @override Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final settings = context.watch<SettingsStore>();
    final brightness = Theme.of(context).brightness;
    return FadeTransition(opacity: fade, child: SnapshotWidget(
      controller: snapshot, mode: SnapshotMode.permissive,
      child: Padding(padding: const EdgeInsets.only(left: 8, bottom: 6),
        child: Align(alignment: Alignment.centerLeft, child: KumoneLiquidSurface(
          radius: 999, blur: settings.chromeBlur,
          backingOpacity: settings.chromeBackingOpacity ?? KumoneGlassOptics.backingOpacity(brightness),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(text!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: brightness == Brightness.light ? Colors.black : Colors.white)),
        )))));
  }
  @override void dispose() { fade.dispose(); snapshot.dispose(); super.dispose(); }
}
