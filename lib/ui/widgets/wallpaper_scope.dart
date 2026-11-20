import 'cached_wallpaper.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/wallpaper_store.dart';
import '../theme/app_theme.dart';

// Wrap the entire root Navigator, so pushed detail/settings routes share the
// wallpaper too. The player route overrides this theme with the original one.
//
// It also owns the app's system-bar tint. The window is edge-to-edge (set up
// natively), so the background painted here runs behind the status bar when
// the "背景延伸" setting is on. With it off, the status bar uses the
// wallpaper's sampled upper-band colour instead of a black/white theme strip.
//
// The now-playing page is untouched by all of this: it sits above this scope
// and draws its own ambient artwork backdrop over the status bar.
class WallpaperScope extends StatelessWidget {
  final Widget child;
  const WallpaperScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperStore>();
    final settings = context.watch<SettingsStore>();
    final extend = settings.backgroundExtend;
    final landscape = MediaQuery.sizeOf(context).aspectRatio > 1;
    final path = wallpaper.pathFor(landscape);
    final dark = wallpaper.darkFor(landscape);
    final statusColor = wallpaper.statusColorFor(landscape);

    if (path == null) {
      // No custom background: pages paint their own opaque chrome, so a
      // transparent bar simply shows the app itself behind it. Icons follow
      // the resolved appearance.
      return _SystemBars(
        darkIcons: _resolveBrightness(context, settings) == Brightness.light,
        extend: true,
        child: child,
      );
    }

    final base = dark ? KumoneTheme.dark(color: settings.accent.color)
        : KumoneTheme.light(color: settings.accent.color);
    final topInset = MediaQuery.paddingOf(context).top;
    final sampled = statusColor ?? base.scaffoldBackgroundColor;
    final statusTint = statusColor == null ? sampled : Color.alphaBlend(
        (dark ? Colors.black : Colors.white).withValues(alpha: .24), sampled);
    final statusDarkIcons = extend ? !dark : statusTint.computeLuminance() > .42;

    return _SystemBars(
      darkIcons: statusDarkIcons,
      extend: extend,
      stripColor: statusTint,
      child: Stack(fit: StackFit.expand, children: [
        Positioned(top: 0, left: 0, right: 0,
          height: MediaQuery.sizeOf(context).height,
          child: const RepaintBoundary(child: KumoneWallpaperBackdrop())),
        if (!extend)
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset,
              child: ColoredBox(color: statusTint)),
        Theme(
            data: base.copyWith(scaffoldBackgroundColor: Colors.transparent),
            child: child),
      ]),
    );
  }

  static Brightness _resolveBrightness(
      BuildContext context, SettingsStore settings) {
    return switch (settings.appearance) {
      AppearanceMode.light => Brightness.light,
      AppearanceMode.dark => Brightness.dark,
      AppearanceMode.system => MediaQuery.platformBrightnessOf(context),
    };
  }
}

// Each moving route needs a real painted background, not just an opaque-route
// flag. Otherwise transparent Scaffolds reveal the outgoing page during a push.
class KumoneWallpaperBackdrop extends StatelessWidget {
  final bool settingsPage;
  const KumoneWallpaperBackdrop({super.key, this.settingsPage = false});

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperStore>();
    final landscape = MediaQuery.sizeOf(context).aspectRatio > 1;
    final path = wallpaper.pathFor(landscape);
    final dark = wallpaper.darkFor(landscape);
    final color = context.watch<SettingsStore?>()?.accent.color ?? KumoneTheme.systemBlue;
    final base = dark ? KumoneTheme.dark(color: color) : KumoneTheme.light(color: color);
    return ColoredBox(
      color: base.scaffoldBackgroundColor,
      child: path != null ? Stack(fit: StackFit.expand, children: [
        if (!wallpaper.previewingBlur)
          CachedWallpaper(path: path, sigma: wallpaper.displayBlur(settingsPage: settingsPage))
        else
        ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: wallpaper.displayBlur(settingsPage: settingsPage),
              sigmaY: wallpaper.displayBlur(settingsPage: settingsPage),
              tileMode: TileMode.clamp),
          enabled: wallpaper.displayBlur(settingsPage: settingsPage) > 0,
          child: Image.file(File(path), fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.expand()),
        ),
        ColoredBox(color: (dark ? Colors.black : Colors.white)
            .withValues(alpha: .24)),
      ]) : const SizedBox.expand(),
    );
  }
}

class KumoneWallpaperRouteSurface extends StatelessWidget {
  final Widget child;
  final bool settingsPage;
  const KumoneWallpaperRouteSurface({super.key, required this.child, this.settingsPage = false});

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperStore?>();
    final landscape = MediaQuery.sizeOf(context).aspectRatio > 1;
    if (wallpaper?.pathFor(landscape) == null) {
      // A snapshot must include an opaque backdrop. Otherwise glass in a
      // transparent subtree samples transparent black during capture.
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor,
          child: child);
    }
    final settings = context.watch<SettingsStore?>();
    final dark = wallpaper!.darkFor(landscape);
    final color = settings?.accent.color ?? KumoneTheme.systemBlue;
    final base = dark ? KumoneTheme.dark(color: color) : KumoneTheme.light(color: color);
    final sampled = wallpaper.statusColorFor(landscape);
    final tint = sampled == null ? base.scaffoldBackgroundColor
        : Color.alphaBlend((dark ? Colors.black : Colors.white)
            .withValues(alpha: .24), sampled);
    return ClipRect(child: Stack(fit: StackFit.expand, children: [
      Positioned.fill(child: RepaintBoundary(child: KumoneWallpaperBackdrop(settingsPage: settingsPage))),
      if (settings?.backgroundExtend == false)
        Positioned(top: 0, left: 0, right: 0,
          height: MediaQuery.paddingOf(context).top,
          child: ColoredBox(color: tint)),
      child,
    ]));
  }
}

/// Applies the app-wide [SystemUiOverlayStyle]: transparent bars when the
/// background is extended, or a wallpaper-sampled status bar otherwise.
class _SystemBars extends StatelessWidget {
  final bool darkIcons;
  final bool extend;
  final Color? stripColor;
  final Widget child;

  const _SystemBars({
    required this.darkIcons,
    required this.extend,
    this.stripColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = extend
        ? Colors.transparent
        : (stripColor ?? Theme.of(context).scaffoldBackgroundColor);
    final iconBrightness = darkIcons ? Brightness.dark : Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: barColor,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}
