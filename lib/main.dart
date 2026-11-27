import 'dart:async';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:provider/provider.dart';
import 'core/player/audio_handler.dart';
import 'core/player/player_controller.dart';
import 'core/storage/account_store.dart';
import 'core/storage/settings_store.dart';
import 'core/storage/app_icon_store.dart';
import 'core/storage/wallpaper_store.dart';
import 'ui/widgets/wallpaper_scope.dart';
import 'ui/pages/app_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await LiquidGlassShaders.ensureLoaded();
  } catch (error) {
    // Unsupported renderers retain the package's frosted fallback.
    debugPrint('Glass shader warmup unavailable: $error');
  }

  final wallpaper = WallpaperStore();
  await wallpaper.load();
  final icons = AppIconStore();
  await icons.load();
  final settings = SettingsStore();
  await settings.load();

  final handler = await AudioService.init(
    builder: () => KumoneAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'im.kumone.audio',
      androidNotificationChannelName: 'Kumone 播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
      androidShowNotificationBadge: false,
      notificationColor: KumoneTheme.systemBlue,
    ),
  );

  await handler.configureCrossfade(settings.crossfadeSeconds, settings.usbExclusive);
  var configuredFade = settings.crossfadeSeconds;
  var configuredUsb = settings.usbExclusive;
  settings.addListener(() {
    if (configuredFade == settings.crossfadeSeconds && configuredUsb == settings.usbExclusive) return;
    configuredFade = settings.crossfadeSeconds;
    configuredUsb = settings.usbExclusive;
    unawaited(handler.configureCrossfade(configuredFade, configuredUsb));
  });
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  session.becomingNoisyEventStream.listen((_) => handler.pause());
  var wasPlayingBeforeInterruption = false;
  session.interruptionEventStream.listen((event) {
    if (event.begin) {
      wasPlayingBeforeInterruption = handler.playbackState.value.playing;
      if (wasPlayingBeforeInterruption) unawaited(handler.pause());
    } else if (event.type == AudioInterruptionType.pause &&
        wasPlayingBeforeInterruption) {
      wasPlayingBeforeInterruption = false;
      unawaited(handler.play());
    }
  });

  await handler.restorePersistedQueue();

  final player = PlayerController(handler);
  await player.setQuality(settings.quality);
  await player.setUnblock(settings.unblock);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: wallpaper),
        ChangeNotifierProvider.value(value: icons),
        ChangeNotifierProvider(create: (_) {
          final account = AccountStore();
          handler.hasVipAccount = () => account.isLoggedIn && account.vipType > 0;
          return account;
        }),
        ChangeNotifierProvider.value(value: player),
      ],
      child: const KumoneApp(),
    ),
  );
}

class KumoneApp extends StatelessWidget {
  const KumoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final mode = switch (settings.appearance) {
      AppearanceMode.system => ThemeMode.system,
      AppearanceMode.dark => ThemeMode.dark,
      AppearanceMode.light => ThemeMode.light,
    };

    return MaterialApp(
      title: 'Kumone',
      debugShowCheckedModeBanner: false,
      theme: KumoneTheme.light(color: settings.accentColor),
      darkTheme: KumoneTheme.dark(color: settings.accentColor),
      themeMode: mode,
      builder: (context, child) => WallpaperScope(child: child!),
      home: const AppShell(),
    );
  }
}
