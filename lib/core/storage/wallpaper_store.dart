import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WallpaperStore extends ChangeNotifier {
  final _prefs = SharedPreferencesAsync();
  String? path;
  bool dark = false;
  double blur = 12;
  bool previewingBlur = false;
  double displayBlur({bool settingsPage = false}) =>
      settingsPage && !previewingBlur && blur < 20 ? 20 : blur;
  ui.Color? statusColor;
  String? landscapePath;
  bool landscapeDark = false;
  ui.Color? landscapeStatusColor;

  String? pathFor(bool landscape) => landscape ? landscapePath : path;
  bool darkFor(bool landscape) => landscape ? landscapeDark : dark;
  ui.Color? statusColorFor(bool landscape) => landscape ? landscapeStatusColor : statusColor;

  // Sample the upper image band, not the app theme's black/white surface.
  Future<void> sampleStatusColor({bool landscape = false}) async {
    final source = pathFor(landscape);
    if (source == null) return;
    try {
      final codec = await ui.instantiateImageCodec(
          await File(source).readAsBytes(),
          targetWidth: 48);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null) {
        var r = 0, g = 0, b = 0, count = 0;
        final rows =
            (frame.image.height * .18).ceil().clamp(1, frame.image.height);
        for (var y = 0; y < rows; y++) {
          for (var x = 0; x < frame.image.width; x++) {
            final i = (y * frame.image.width + x) * 4;
            r += data.getUint8(i);
            g += data.getUint8(i + 1);
            b += data.getUint8(i + 2);
            count++;
          }
        }
        if (pathFor(landscape) == source) {
          final color = ui.Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
          if (landscape) { landscapeStatusColor = color; } else { statusColor = color; }
        }
      }
      frame.image.dispose();
      codec.dispose();
    } catch (_) {/* Invalid/missing wallpaper retains the theme fallback. */}
  }

  bool get enabled => path != null;

  Future<void> load() async {
    final value = await _prefs.getString('wallpaperPath');
    if (value != null && await File(value).exists()) path = value;
    dark = await _prefs.getBool('wallpaperDark') ?? false;
    final wide = await _prefs.getString('landscapeWallpaperPath');
    if (wide != null && await File(wide).exists()) landscapePath = wide;
    landscapeDark = await _prefs.getBool('landscapeWallpaperDark') ?? false;
    await sampleStatusColor(landscape: true);
    blur =
        (await _prefs.getDouble('wallpaperBlur') ?? 12).clamp(0, 40).toDouble();
    await sampleStatusColor();
    notifyListeners();
  }

  Future<void> pick({bool landscape = false,
      Future<Uint8List?> Function(Uint8List bytes)? crop}) async {
    final image = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 2400, maxHeight: 3200);
    if (image == null) return;
    final original = await image.readAsBytes();
    final bytes = crop == null ? original : await crop(original);
    if (bytes == null) return;
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 48, targetHeight: 48);
    final frame = await codec.getNextFrame();
    final pixels =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    var light = 0.0;
    if (pixels != null) {
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        light += (.2126 * pixels.getUint8(i) +
                .7152 * pixels.getUint8(i + 1) +
                .0722 * pixels.getUint8(i + 2)) /
            255;
      }
      light /= pixels.lengthInBytes / 4;
    }
    frame.image.dispose();
    codec.dispose();
    final root = await getApplicationSupportDirectory();
    final file = File(p.join(
        root.path, 'wallpaper_${DateTime.now().microsecondsSinceEpoch}.image'));
    await file.writeAsBytes(bytes, flush: true);
    final previous = pathFor(landscape);
    if (landscape) {
      landscapeDark = light < .52;
      landscapePath = file.path;
      await _prefs.setBool('landscapeWallpaperDark', landscapeDark);
      await _prefs.setString('landscapeWallpaperPath', file.path);
    } else {
      dark = light < .52;
      path = file.path;
      await _prefs.setBool('wallpaperDark', dark);
      await _prefs.setString('wallpaperPath', file.path);
    }
    await sampleStatusColor(landscape: landscape);
    notifyListeners();
    if (previous != null && previous != pathFor(landscape)) {
      try {
        await File(previous).delete();
      } catch (_) {}
    }
  }

  void previewBlur(double value) {
    previewingBlur = true;
    blur = value.clamp(0, 40).toDouble();
    notifyListeners();
  }

  Future<void> saveBlur(double value) async {
    blur = value.clamp(0, 40).toDouble();
    previewingBlur = false;
    notifyListeners();
    await _prefs.setDouble('wallpaperBlur', blur);
  }

  Future<void> clear({bool landscape = false}) async {
    final previous = pathFor(landscape);
    await _prefs.remove(landscape ? 'landscapeWallpaperPath' : 'wallpaperPath');
    if (landscape) { landscapePath = null; landscapeStatusColor = null; }
    else { path = null; statusColor = null; }
    notifyListeners();
    if (previous != null) {
      try {
        await File(previous).delete();
      } catch (_) {}
    }
  }
}
