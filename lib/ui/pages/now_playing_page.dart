import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/models/lyrics.dart';
import '../widgets/player_dual_pane.dart';
import '../widgets/marquee_text.dart';
import '../widgets/auto_scroll_metadata.dart';
import '../widgets/lyric_effects.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';
import '../../core/storage/settings_store.dart';
import '../widgets/common.dart';
import 'queue_page.dart';
import 'details_page.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  ParsedLyrics? lyrics;
  int? loadedId;
  bool showLyrics = false;
  bool showQueue = false;
  bool lyricLoading = false;
  bool lyricFailed = false;
  bool _dependenciesInitialized = false;
  NowPlayingMode? _lastMode;

  // Artwork palette state is independent from Android system-bar handling.
  // It is shared by the player backdrop, More menu, and queue surface.
  ImageStream? _artworkStream;
  ImageStreamListener? _artworkListener;
  String? _artworkKey;
  _ArtworkColors _artworkColors = _ArtworkColors.fallback;

  static const _systemUiChannel = MethodChannel('im.kumone/system_ui');
  bool? _lastRequestedDarkStatusIcons;
  int? _lastRequestedStatusBarPrimary;
  int? _lastRequestedStatusBarSecondary;
  Animation<double>? _coveringRoute;
  bool _barsSuspended = false;
  void _syncCoveredBars() {
    final covered = (_coveringRoute?.value ?? 0) > 0;
    if (covered == _barsSuspended || !mounted) return;
    _barsSuspended = covered;
    if (covered) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        unawaited(_systemUiChannel.invokeMethod<void>('exitNowPlaying', {
          'backgroundColor': _normalSystemBarColor.toARGB32(),
          'darkIcons': _normalDarkIcons,
        }));
      }
    } else {
      _lastRequestedDarkStatusIcons = null;
      _lastRequestedStatusBarPrimary = null;
      _lastRequestedStatusBarSecondary = null;
      _requestStatusBarAppearance(_artworkColors.primary.computeLuminance() > .52,
          _artworkColors.primary, _artworkColors.secondary);
    }
  }
  bool _normalDarkIcons = true;
  Color _normalSystemBarColor = const Color(0xFFF8F8FA);

  @override
  void initState() {
    super.initState();
    // On Android 14, Flutter's edge-to-edge mode alone does not guarantee
    // that the host window is actually drawing behind the status bar. The
    // native bridge enables that at the Activity/window level. Android 15+
    // already enforces edge-to-edge, so the same call is harmless there.
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_systemUiChannel.invokeMethod<void>('enterNowPlaying', {
        'darkIcons': false,
        'primaryColor': _artworkColors.primary.toARGB32(),
        'secondaryColor': _artworkColors.secondary.toARGB32(),
      }));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final covering = ModalRoute.of(context)?.secondaryAnimation;
    if (_coveringRoute != covering) {
      _coveringRoute?.removeListener(_syncCoveredBars);
      _coveringRoute = covering;
      covering?.addListener(_syncCoveredBars);
    }
    final player = context.read<PlayerController>();
    final settings = context.read<SettingsStore>();
    final theme = Theme.of(context);
    _normalDarkIcons = kumoneGlassStatusBarStyle(context).statusBarIconBrightness == Brightness.dark;
    _normalSystemBarColor = theme.scaffoldBackgroundColor;
    if (!_dependenciesInitialized) {
      _dependenciesInitialized = true;
      _lastMode = settings.nowPlaying;
      showLyrics = false;
      showQueue = false;
    } else if (_lastMode != settings.nowPlaying) {
      _lastMode = settings.nowPlaying;
      showLyrics = false;
      showQueue = false;
    }
    _load(player.currentTrack);
  }

  Future<void> _load(Track? track) async {
    if (track == null || loadedId == track.id) return;
    loadedId = track.id;
    setState(() {
      lyrics = null;
      lyricLoading = true;
      lyricFailed = false;
    });
    try {
      final parsed = await context.read<PlayerController>().lyrics(track);
      if (!mounted || loadedId != track.id) return;
      setState(() {
        lyrics = parsed;
        lyricLoading = false;
        lyricFailed = parsed == null;
      });
    } catch (_) {
      if (!mounted || loadedId != track.id) return;
      setState(() {
        lyrics = null;
        lyricLoading = false;
        lyricFailed = true;
      });
    }
  }

  Future<void> _retryLyrics() async {
    final track = context.read<PlayerController>().currentTrack;
    if (track == null) return;
    context.read<PlayerController>().invalidateLyrics(track.id);
    loadedId = null;
    await _load(track);
  }

  void _scheduleArtworkPalette(Track track) {
    final url = track.album.picUrl?.trim() ?? '';
    final key = '${track.id}|$url';
    if (_artworkKey == key) return;
    _artworkKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _artworkKey != key) return;
      _loadArtworkPalette(track, key);
    });
  }

  void _loadArtworkPalette(Track track, String key) {
    final oldStream = _artworkStream;
    final oldListener = _artworkListener;
    if (oldStream != null && oldListener != null) {
      oldStream.removeListener(oldListener);
    }
    _artworkStream = null;
    _artworkListener = null;

    final url = track.album.picUrl?.trim() ?? '';
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _artworkColors = _ArtworkColors.fallback;
        });
      }
      return;
    }

    var normalized = url;
    if (normalized.startsWith('//')) normalized = 'https:$normalized';
    if (normalized.startsWith('http://')) {
      normalized = 'https://${normalized.substring(7)}';
    }
    final uri = Uri.tryParse(normalized);
    final candidates = <String>[];
    if (uri != null && uri.host.isNotEmpty) {
      final hosts = <String>[uri.host];
      if (RegExp(r'^p[1-4]\.music\.126\.net$').hasMatch(uri.host)) {
        for (final host in const [
          'p1.music.126.net',
          'p2.music.126.net',
          'p3.music.126.net',
          'p4.music.126.net',
        ]) {
          if (!hosts.contains(host)) hosts.add(host);
        }
      }
      final original = uri.replace(host: hosts.first).toString();
      candidates.add(original);
      for (final size in const [512, 300]) {
        final params = Map<String, String>.from(uri.queryParameters);
        params['param'] = '${size}y$size';
        candidates.add(
            uri.replace(host: hosts.first, queryParameters: params).toString());
      }
      for (final host in hosts.skip(1)) {
        final params = Map<String, String>.from(uri.queryParameters);
        params['param'] = '512y512';
        candidates
            .add(uri.replace(host: host, queryParameters: params).toString());
      }
    } else {
      candidates.add(normalized);
    }
    final uniqueCandidates = candidates.toSet().toList(growable: false);

    void useFallback() {
      if (!mounted || _artworkKey != key) return;
      setState(() {
        _artworkColors = _ArtworkColors.fallback;
      });
    }

    void loadCandidate(int index) {
      if (!mounted || _artworkKey != key) return;
      if (index >= uniqueCandidates.length) {
        useFallback();
        return;
      }

      final provider = ResizeImage(
        CachedNetworkImageProvider(
          uniqueCandidates[index],
          headers: const {
            'Referer': 'https://music.163.com/',
            'User-Agent': 'Mozilla/5.0 (Android) AppleWebKit/537.36 '
                'Chrome/125.0 Mobile Safari/537.36',
          },
        ),
        width: 10,
        height: 10,
      );
      final stream = provider.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (imageInfo, _) async {
          try {
            final data = await imageInfo.image.toByteData(
              format: ImageByteFormat.rawRgba,
            );
            if (!mounted || data == null || _artworkKey != key) return;

            final colors = _ArtworkPalette.extract(
              data.buffer.asUint8List(),
              imageInfo.image.width,
              imageInfo.image.height,
            );
            // The same artwork-derived palette is shared by the player
            // backdrop, More menu, and queue surface.
            if (!mounted || _artworkKey != key) return;
            setState(() {
              _artworkColors = colors;
            });
            _requestStatusBarAppearance(
              colors.primary.computeLuminance() > .52,
              colors.primary,
              colors.secondary,
            );
          } catch (_) {
            stream.removeListener(listener);
            loadCandidate(index + 1);
          }
        },
        onError: (Object _, StackTrace? __) {
          stream.removeListener(listener);
          loadCandidate(index + 1);
        },
      );
      stream.addListener(listener);
      _artworkStream = stream;
      _artworkListener = listener;
    }

    loadCandidate(0);
  }

  @override
  void dispose() {
    _coveringRoute?.removeListener(_syncCoveredBars);
    final stream = _artworkStream;
    final listener = _artworkListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    // Restore the host window when leaving the player. On Android 15/16 the
    // platform keeps edge-to-edge by design; the native side therefore only
    // restores the system-bar icon appearance there. Android 14 also restores
    // the pre-player fitted-window layout and normal bar colors.
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_systemUiChannel.invokeMethod<void>('exitNowPlaying', {
        'backgroundColor': _normalSystemBarColor.toARGB32(),
        'darkIcons': _normalDarkIcons,
      }));
    }
    super.dispose();
  }

  void _openQueue() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .48),
      builder: (_) => QueuePage(
        primary: _artworkColors.primary,
        secondary: _artworkColors.secondary,
      ),
    );
  }

  void _openArtist(ArtistRef artist) {
    if (artist.id <= 0) return;
    Navigator.of(context).push(kumonePageRoute(ArtistPage(id: artist.id)));
  }

  void _openAlbum(AlbumRef album) {
    if (album.id <= 0) return;
    Navigator.of(context).push(kumonePageRoute(AlbumPage(id: album.id)));
  }

  void _requestStatusBarAppearance(
    bool darkIcons,
    Color primary,
    Color secondary,
  ) {
    if (defaultTargetPlatform != TargetPlatform.android || _barsSuspended ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }

    final primaryValue = primary.toARGB32();
    final secondaryValue = secondary.toARGB32();
    if (_lastRequestedDarkStatusIcons == darkIcons &&
        _lastRequestedStatusBarPrimary == primaryValue &&
        _lastRequestedStatusBarSecondary == secondaryValue) {
      return;
    }
    _lastRequestedDarkStatusIcons = darkIcons;
    _lastRequestedStatusBarPrimary = primaryValue;
    _lastRequestedStatusBarSecondary = secondaryValue;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _barsSuspended || ModalRoute.of(context)?.isCurrent == false) return;
      unawaited(_systemUiChannel.invokeMethod<void>('enterNowPlaying', {
        'darkIcons': darkIcons,
        'primaryColor': primaryValue,
        'secondaryColor': secondaryValue,
      }));
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final settings = context.watch<SettingsStore>();
    final track = player.currentTrack;
    if (track == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('暂无播放')),
      );
    }
    if (loadedId != track.id && !lyricLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(track);
      });
    }

    _scheduleArtworkPalette(track);

    final useDarkStatusIcons = _artworkColors.primary.computeLuminance() > .52;
    final statusIconBrightness =
        useDarkStatusIcons ? Brightness.dark : Brightness.light;
    _requestStatusBarAppearance(
      useDarkStatusIcons,
      _artworkColors.primary,
      _artworkColors.secondary,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: statusIconBrightness,
        statusBarBrightness:
            useDarkStatusIcons ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: statusIconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: _PlayerDragDismiss(child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: _ArtworkBackdrop(colors: _artworkColors),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 840 ||
                      constraints.maxHeight >= constraints.maxWidth;
                  final dualPane = settings.landscapeDualPane &&
                      constraints.maxWidth >= 700 &&
                      constraints.maxWidth > constraints.maxHeight &&
                      constraints.maxHeight >= 280;
                  if (dualPane) {
                    return Column(children: [
                      _TopChrome(
                          hideHeart: true,
                          track: track,
                          menuPrimary: _artworkColors.primary,
                          menuSecondary: _artworkColors.secondary,
                          onClose: () => Navigator.pop(context),
                          onOpenAlbum: _openAlbum,
                          onOpenArtist: _openArtist),
                      Expanded(child: KumonePlayerDualPane(
                        playerBuilder: (cover, spacious) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Artwork(url: track.album.picUrl, size: cover,
                              radius: spacious ? 24 : 18, shadow: false),
                            SizedBox(height: spacious ? 24 : 10),
                            _ImmersiveMetadata(track: track, centered: true,
                              onOpenArtist: _openArtist, onOpenAlbum: _openAlbum),
                            SizedBox(height: spacious ? 18 : 6),
                            _PlaybackControls(track: track, player: player,
                              onQueue: () => setState(() => showQueue = !showQueue),
                              queueSelected: showQueue, showVolume: spacious,
                              minimal: !spacious, dualPane: true,
                              immersive: false, showLyrics: true,
                              onToggleLyrics: () {}),
                          ]),
                        lyrics: showQueue
                          ? QueueListPanel(embedded: true,
                              foregroundColor: Colors.white,
                              secondaryForegroundColor: Colors.white70)
                          : _LyricsSide(lyrics: lyrics, player: player,
                              loading: lyricLoading, failed: lyricFailed,
                              onRetry: _retryLyrics),
                      )),
                    ]);
                  }
                  return Column(
                    children: [
                      _PlayerDismissHandle(onClose: () => Navigator.of(context).maybePop()),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 36 : 44,
                            2,
                            compact ? 36 : 44,
                            0,
                          ),
                          child: _ModeContent(
                            mode: settings.nowPlaying,
                            compact: compact,
                            track: track,
                            player: player,
                            showLyrics: showLyrics,
                            showQueue: showQueue,
                            lyrics: lyrics,
                            lyricLoading: lyricLoading,
                            lyricFailed: lyricFailed,
                            onRetryLyrics: _retryLyrics,
                            onOpenArtist: _openArtist,
                            onOpenAlbum: _openAlbum,
                            queuePrimary: _artworkColors.primary,
                            queueSecondary: _artworkColors.secondary,
                            onToggleLyrics: () => setState(() {
                              showLyrics = !showLyrics;
                              showQueue = false;
                            }),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 36 : 44,
                          6,
                          compact ? 36 : 44,
                          compact ? 10 : 16,
                        ),
                        child: _PlaybackControls(
                          track: track,
                          player: player,
                          onQueue: _openQueue,
                          showVolume: true,
                          timelineOffset: _portraitTimelineOffset(
                            constraints.maxWidth - (compact ? 72 : 88),
                            constraints.maxHeight - 28 - 2 -
                              ((constraints.maxWidth - (compact ? 72 : 88)) < 340 ? 240 : 256) -
                              (compact ? 16 : 22),
                            settings.nowPlaying == NowPlayingMode.minimal),
                          minimal: false,
                          immersive: true,
                          showLyrics: showLyrics,
                          onToggleLyrics: () => setState(() {
                            showLyrics = !showLyrics;
                            showQueue = false;
                          }),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      )),
    );
  }
}

class _ArtworkColors {
  final Color primary;
  final Color secondary;

  const _ArtworkColors({required this.primary, required this.secondary});

  static const fallback = _ArtworkColors(
    primary: Color(0xFF292933),
    secondary: Color(0xFF17171F),
  );

  @override
  bool operator ==(Object other) =>
      other is _ArtworkColors &&
      other.primary.toARGB32() == primary.toARGB32() &&
      other.secondary.toARGB32() == secondary.toARGB32();

  @override
  int get hashCode => Object.hash(primary.toARGB32(), secondary.toARGB32());
}

class _ArtworkPalette {
  static _ArtworkColors extract(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return _ArtworkColors.fallback;
    }

    final samples =
        <({double hue, double saturation, double brightness, double weight})>[];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final alpha = rgba[offset + 3] / 255.0;
        if (alpha <= .1) continue;

        final color = Color.fromARGB(
          255,
          rgba[offset],
          rgba[offset + 1],
          rgba[offset + 2],
        );
        final hsv = HSVColor.fromColor(color);
        final saturation = hsv.saturation;
        final brightness = hsv.value;
        final weight = math.max(
          saturation * (1 - (brightness - .55).abs()),
          .01,
        );
        samples.add((
          hue: hsv.hue / 360.0,
          saturation: saturation,
          brightness: brightness,
          weight: weight,
        ));
      }
    }

    if (samples.isEmpty) return _ArtworkColors.fallback;

    // Ignore the weakest color samples. This keeps a vivid dominant artwork
    // (for example the cyan/blue cover in the reference) from being pulled
    // toward dark lettering, borders, or tiny accent regions.
    samples.sort((a, b) => b.weight.compareTo(a.weight));
    final keep = math.max(1, (samples.length * .45).ceil());

    var sinSum = 0.0;
    var cosSum = 0.0;
    var satSum = 0.0;
    var brightSum = 0.0;
    var weightSum = 0.0;
    for (final sample in samples.take(keep)) {
      final angle = sample.hue * math.pi * 2;
      sinSum += math.sin(angle) * sample.weight;
      cosSum += math.cos(angle) * sample.weight;
      satSum += sample.saturation * sample.weight;
      brightSum += sample.brightness * sample.weight;
      weightSum += sample.weight;
    }

    if (weightSum <= 0) return _ArtworkColors.fallback;

    var hue = math.atan2(sinSum, cosSum) / (math.pi * 2);
    if (hue < 0) hue += 1;
    final saturation = math.min((satSum / weightSum) * 1.15, .72);
    final brightness = brightSum / weightSum;

    final primary = HSVColor.fromAHSV(
      1,
      hue * 360,
      saturation,
      brightness.clamp(.32, .50).toDouble(),
    ).toColor();
    final secondary = HSVColor.fromAHSV(
      1,
      ((hue + .06) % 1) * 360,
      math.min(saturation * 1.1, .80),
      (brightness * .50).clamp(.12, .26).toDouble(),
    ).toColor();

    return _ArtworkColors(primary: primary, secondary: secondary);
  }
}

class _ArtworkBackdrop extends StatelessWidget {
  final _ArtworkColors colors;
  const _ArtworkBackdrop({required this.colors});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, colors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Color.fromRGBO(255, 255, 255, .12),
                  Color.fromRGBO(255, 255, 255, 0),
                ],
                center: Alignment.topLeft,
                radius: .95,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.fromRGBO(0, 0, 0, 0),
                  Color.fromRGBO(0, 0, 0, .35),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  final bool hideHeart;
  final Track track;
  final Color menuPrimary;
  final Color menuSecondary;
  final VoidCallback onClose;
  final ValueChanged<AlbumRef> onOpenAlbum;
  final ValueChanged<ArtistRef> onOpenArtist;

  const _TopChrome({
    this.hideHeart = false,
    required this.track,
    required this.menuPrimary,
    required this.menuSecondary,
    required this.onClose,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountStore>();
    final liked = account.liked(track.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 4),
      child: Row(
        children: [
          SizedBox(width: 64, child: _PlayerDismissHandle(onClose: onClose)),
          const Spacer(),
          if (!hideHeart) _RoundGlassButton(
            icon: liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            onTap: () async {
              try {
                await account.toggleLike(track.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            tooltip: liked ? '取消喜欢' : '喜欢',
            active: liked,
          ),
          const SizedBox(width: 6),
          TrackActionMenu(
            track: track,
            onOpenAlbum: onOpenAlbum,
            onOpenArtist: onOpenArtist,
            glassMenu: true,
            plainPlayerButton: true,
            glassMenuPrimary: menuPrimary,
            glassMenuSecondary: menuSecondary,
          ),
        ],
      ),
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;
  final double iconSize;
  final double hitSize;

  const _RoundGlassButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
    this.iconSize = 23,
    this.hitSize = 42,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = active ? AppAccent.appleRed.color : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withValues(alpha: .10),
          highlightColor: Colors.white.withValues(alpha: .06),
          onTap: onTap,
          child: SizedBox(
            width: hitSize,
            height: hitSize,
            child: Icon(
              icon,
              color: foreground,
              size: iconSize,
              shadows: const [],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeContent extends StatelessWidget {
  final NowPlayingMode mode;
  final bool compact;
  final Track track;
  final PlayerController player;
  final bool showLyrics;
  final bool showQueue;
  final ParsedLyrics? lyrics;
  final bool lyricLoading;
  final bool lyricFailed;
  final VoidCallback onRetryLyrics;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;
  final VoidCallback onToggleLyrics;
  final Color? queuePrimary;
  final Color? queueSecondary;

  const _ModeContent({
    required this.mode,
    required this.compact,
    required this.track,
    required this.player,
    required this.showLyrics,
    required this.showQueue,
    required this.lyrics,
    required this.lyricLoading,
    required this.lyricFailed,
    required this.onRetryLyrics,
    required this.onOpenArtist,
    required this.onOpenAlbum,
    required this.onToggleLyrics,
    this.queuePrimary,
    this.queueSecondary,
  });

  @override
  Widget build(BuildContext context) {
    if (showQueue) {
      return QueueListPanel(
        embedded: true,
        primary: queuePrimary,
        secondary: queueSecondary,
      );
    }
    switch (mode) {
      case NowPlayingMode.immersive:
        if (compact) {
          return _ImmersiveMobileContent(
            track: track,
            player: player,
            showLyrics: showLyrics,
            lyrics: lyrics,
            lyricLoading: lyricLoading,
            lyricFailed: lyricFailed,
            onRetryLyrics: onRetryLyrics,
            onOpenArtist: onOpenArtist,
            onOpenAlbum: onOpenAlbum,
            onToggleLyrics: onToggleLyrics,
          );
        }
        return _ImmersiveModeContent(
          compact: compact,
          track: track,
          player: player,
          showLyrics: showLyrics,
          lyrics: lyrics,
          lyricLoading: lyricLoading,
          lyricFailed: lyricFailed,
          onRetryLyrics: onRetryLyrics,
          onOpenArtist: onOpenArtist,
          onOpenAlbum: onOpenAlbum,
        );
      case NowPlayingMode.minimal:
        if (compact) {
          return _ImmersiveMobileContent(
            minimal: true,
            lyricLoading: lyricLoading,
            lyricFailed: lyricFailed,
            track: track,
            player: player,
            showLyrics: showLyrics,
            lyrics: lyrics,
            onRetryLyrics: onRetryLyrics,
            onOpenArtist: onOpenArtist,
            onOpenAlbum: onOpenAlbum,
            onToggleLyrics: onToggleLyrics,
          );
        }
        return _MinimalModeContent(
          compact: compact,
          track: track,
          player: player,
          showLyrics: showLyrics,
          lyrics: lyrics,
          onToggleLyrics: onToggleLyrics,
          onOpenArtist: onOpenArtist,
          onOpenAlbum: onOpenAlbum,
        );
    }
  }
}

class _ImmersiveMobileContent extends StatelessWidget {
  final bool minimal;
  final Track track;
  final PlayerController player;
  final bool showLyrics;
  final ParsedLyrics? lyrics;
  final bool lyricLoading;
  final bool lyricFailed;
  final VoidCallback onRetryLyrics;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;
  final VoidCallback onToggleLyrics;

  const _ImmersiveMobileContent({
    this.minimal = false,
    required this.track,
    required this.player,
    required this.showLyrics,
    required this.lyrics,
    required this.lyricLoading,
    required this.lyricFailed,
    required this.onRetryLyrics,
    required this.onOpenArtist,
    required this.onOpenAlbum,
    required this.onToggleLyrics,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, bounds) {
      const headingHeight = 68.0;
      final available = math.max(0.0, bounds.maxHeight - headingHeight);
      final reserved = minimal ? 18.0 : 109.0;
      final coverSize = math.min(
        math.min(minimal ? 390.0 : 340.0,
          math.min(bounds.maxWidth * (minimal ? .94 : .80),
            bounds.maxHeight * (minimal ? .68 : .56))),
        math.max(24.0, available - reserved));
      final extra = math.max(0.0, available - reserved - coverSize);
      final coverTop = headingHeight + 12 + extra / 2;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero : const Duration(milliseconds: 420);
      return Stack(children: [
        Positioned(top: headingHeight + 16, bottom: 0, left: 0, right: 0,
          child: ExcludeSemantics(excluding: !showLyrics, child: IgnorePointer(ignoring: !showLyrics,
            child: AnimatedOpacity(opacity: showLyrics ? 1 : 0,
              duration: duration, curve: Curves.easeOutCubic,
              child: _ImmersiveLyricsColumn(lyrics: lyrics, player: player,
                loading: lyricLoading, failed: lyricFailed, onRetry: onRetryLyrics))))),
        if (!minimal) Positioned(left: 0, right: 0, bottom: 6,
          child: IgnorePointer(ignoring: showLyrics,
            child: AnimatedOpacity(opacity: showLyrics ? 0 : 1,
              duration: duration, child: _ThreeLineLyricPreview(
                key: const ValueKey('portrait-preview'),
                lyrics: lyrics, player: player, onTap: onToggleLyrics)))),
        Positioned(top: 0, left: 0, right: 0, height: headingHeight,
          child: _MobilePlayerHeading(track: track, showCover: showLyrics,
            externalCover: true, duration: duration,
            onCoverTap: onToggleLyrics, onOpenArtist: onOpenArtist,
            onOpenAlbum: onOpenAlbum)),
        AnimatedPositioned(duration: duration, curve: Curves.easeInOutCubic,
          top: showLyrics ? 3 : coverTop,
          left: showLyrics ? 0 : (bounds.maxWidth - coverSize) / 2,
          width: showLyrics ? 62 : coverSize,
          height: showLyrics ? 62 : coverSize,
          child: GestureDetector(onTap: onToggleLyrics,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: showLyrics ? 12 : 22), duration: duration,
              builder: (context, radius, _) => Artwork(url: track.album.picUrl,
                size: showLyrics ? 62 : coverSize, radius: radius,
                shadow: false, border: false)))),
      ]);
    });
  }
}

class _ImmersiveMetadata extends StatelessWidget {
  // Both compact immersive states intentionally share exactly the same
  // metadata typography so switching between artwork and lyrics never
  // changes the visual scale of the title/subtitle block.
  static const double titleFontSize = 21.0;
  static const double subtitleFontSize = 13.5;

  final Track track;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;

  final bool centered;

  const _ImmersiveMetadata({
    this.centered = false,
    required this.track,
    required this.onOpenArtist,
    required this.onOpenAlbum,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          track.name,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            height: 1.15,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 22,
          child: AutoScrollMetadata(
            centered: centered,
            identity: '${track.id}:${track.artistNames}:${track.album.name}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < track.artists.length; i++) ...[
                  if (i > 0)
                    const Text(
                      ' / ',
                      style: TextStyle(
                          color: Colors.white60, fontSize: subtitleFontSize),
                    ),
                  InkWell(
                    onTap: () => onOpenArtist(track.artists[i]),
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 1,
                        vertical: 2,
                      ),
                      child: Text(
                        track.artists[i].name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: subtitleFontSize,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
                if (track.album.id > 0 && track.album.name.isNotEmpty) ...[
                  const Text(
                    ' · ',
                    style: TextStyle(
                        color: Colors.white54, fontSize: subtitleFontSize),
                  ),
                  InkWell(
                    onTap: () => onOpenAlbum(track.album),
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 1,
                        vertical: 2,
                      ),
                      child: Text(
                        track.album.name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: subtitleFontSize,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreeLineLyricPreview extends StatelessWidget {
  final ParsedLyrics? lyrics;
  final PlayerController player;
  final VoidCallback onTap;

  const _ThreeLineLyricPreview({
    super.key,
    required this.lyrics,
    required this.player,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = lyrics;
    if (parsed == null || parsed.lines.isEmpty) {
      return const SizedBox(height: 82, width: double.infinity);
    }

    final active = parsed
            .activeIndex(player.position)
            ?.clamp(0, parsed.lines.length - 1) ??
        0;
    final rows = <LyricLine?>[
      active > 0 ? parsed.lines[active - 1] : null,
      parsed.lines[active],
      active + 1 < parsed.lines.length ? parsed.lines[active + 1] : null,
    ];

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 82,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++)
              if (rows[i] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: MarqueeText(
                    rows[i]!.text,
                    scrollEnabled: i == 1,
                    pixelsPerSecond: 46,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: i == 1 ? 1 : .42,
                      ),
                      fontSize: i == 1 ? 20 : 14,
                      height: 1.2,
                      fontWeight: i == 1 ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ImmersiveLyricsColumn extends StatefulWidget {
  final ParsedLyrics? lyrics;
  final PlayerController player;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  const _ImmersiveLyricsColumn({
    required this.lyrics,
    required this.player,
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  @override
  State<_ImmersiveLyricsColumn> createState() => _ImmersiveLyricsColumnState();
}

class _ImmersiveLyricsColumnState extends State<_ImmersiveLyricsColumn> {
  final ScrollController controller = ScrollController();
  final Map<int, GlobalKey> lineKeys = {};
  int? lastActive;
  bool userScrolling = false;
  bool scrollScheduled = false;
  Timer? _browseTimer;

  GlobalKey _keyFor(int index) => lineKeys.putIfAbsent(index, GlobalKey.new);

  void _scheduleScroll(int active) {
    if (scrollScheduled) return;
    scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollScheduled = false;
      if (!mounted || userScrolling) return;
      final target = lineKeys[active]?.currentContext;
      if (target == null) return;
      final jump = lastActive != null && (active - lastActive!).abs() > 6;
      lastActive = active;
      Scrollable.ensureVisible(
        target,
        alignment: .34,
        duration: jump ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _browseTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.lyrics;
    if (parsed == null) {
      if (widget.loading) {
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.failed ? Icons.refresh_rounded : Icons.lyrics_outlined,
              color: Colors.white60,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              widget.failed ? '歌词加载失败' : '暂无歌词',
              style: const TextStyle(color: Colors.white70),
            ),
            if (widget.failed)
              TextButton(
                onPressed: widget.onRetry,
                child: const Text('重新加载'),
              ),
          ],
        ),
      );
    }
    if (parsed.lines.isEmpty) {
      return Center(
        child: Text(
          parsed.instrumental ? '纯音乐，请欣赏' : '暂无歌词',
          style: const TextStyle(color: Colors.white60),
        ),
      );
    }

    final active = parsed.activeIndex(widget.player.position) ?? 0;
    _scheduleScroll(active);
    final settings = context.watch<SettingsStore>();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _browseTimer?.cancel();
          setState(() => userScrolling = true);
        } else if (notification is ScrollEndNotification && userScrolling) {
          _browseTimer?.cancel();
          _browseTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) setState(() => userScrolling = false);
          });
        }
        return false;
      },
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          stops: [0, .12, .84, 1],
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: controller,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 66, 0, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < parsed.lines.length; i++)
                GestureDetector(
                  key: _keyFor(i),
                  onTap: () {
                    lastActive = null;
                    userScrolling = false;
                    unawaited(
                      widget.player.seek(
                        Duration(milliseconds: parsed.lines[i].startMs),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: LyricDistanceBlur(
                      radius: lyricBlurRadius(
                          i, active, settings.lyricBlur, userScrolling),
                      child: KumoneImmersiveLyricLine(
                        line: parsed.lines[i],
                        current: i == active,
                        settings: settings,
                        playbackMs: widget.player.position.inMilliseconds,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class KumoneImmersiveLyricLine extends StatelessWidget {
  final LyricLine line;
  final bool current;
  final SettingsStore settings;
  final int playbackMs;

  const KumoneImmersiveLyricLine({
    super.key,
    required this.line,
    required this.current,
    required this.settings,
    required this.playbackMs,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (settings.annotation == LyricsAnnotationMode.romaji &&
        line.romaji?.trim().isNotEmpty == true) {
      children.add(
        Text(
          line.romaji!,
          style: TextStyle(
            color: Colors.white.withValues(alpha: current ? .72 : .38),
            fontSize: (current ? 15 : 13) * settings.lyricFontScale,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      children.add(const SizedBox(height: 3));
    }

    Widget main;
    if (current && settings.verbatim && line.words.isNotEmpty) {
      main = _KaraokeLineText(
        line: line,
        playbackMs: playbackMs,
        fontSize: 26 * settings.lyricFontScale,
      );
    } else if (settings.annotation == LyricsAnnotationMode.furigana &&
        line.furigana.isNotEmpty) {
      main = _FuriganaLineText(
        line: line,
        current: current,
        playbackMs: playbackMs,
        settings: settings,
      );
    } else {
      main = Text(
        line.text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: current ? 1 : .45),
          fontSize: (current ? 26 : 21) * settings.lyricFontScale,
          height: 1.25,
          fontWeight: current ? FontWeight.w800 : FontWeight.w600,
        ),
      );
    }
    children.add(main);

    if (settings.translation && line.translation?.trim().isNotEmpty == true) {
      children.add(const SizedBox(height: 5));
      children.add(
        Text(
          line.translation!,
          style: TextStyle(
            color: Colors.white.withValues(alpha: current ? .72 : .35),
            fontSize: (current ? 16 : 14) * settings.lyricFontScale,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _FuriganaLineText extends StatelessWidget {
  final LyricLine line;
  final bool current;
  final int playbackMs;
  final SettingsStore settings;

  const _FuriganaLineText({
    required this.line,
    required this.current,
    required this.playbackMs,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = <_WordCharRange>[];
    var cursor = 0;
    for (final word in line.words) {
      final length = word.text.characters.length;
      ranges.add(_WordCharRange(cursor, cursor + length, word));
      cursor += length;
    }

    var absolute = 0;
    final children = <Widget>[];
    for (final segment in line.furigana) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(right: 1),
          child: _ImmersiveFuriganaSegment(
            segment: segment,
            current: current,
            playbackMs: playbackMs,
            absoluteStart: absolute,
            ranges: ranges,
            fontScale: settings.lyricFontScale,
          ),
        ),
      );
      absolute += segment.text.characters.length;
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 0,
      runSpacing: 3,
      children: children,
    );
  }
}

class _ImmersiveFuriganaSegment extends StatelessWidget {
  final FuriganaSegment segment;
  final bool current;
  final int playbackMs;
  final int absoluteStart;
  final List<_WordCharRange> ranges;
  final double fontScale;

  const _ImmersiveFuriganaSegment({
    required this.segment,
    required this.current,
    required this.playbackMs,
    required this.absoluteStart,
    required this.ranges,
    required this.fontScale,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: Colors.white.withValues(alpha: current ? 1 : .45),
      fontSize: (current ? 26 : 21) * fontScale,
      height: 1.2,
      fontWeight: current ? FontWeight.w800 : FontWeight.w600,
    );
    final spans = <TextSpan>[];
    final chars = segment.text.characters.toList();
    for (var i = 0; i < chars.length; i++) {
      final absolute = absoluteStart + i;
      var color = base.color;
      if (current && ranges.isNotEmpty) {
        for (final range in ranges) {
          if (absolute >= range.start && absolute < range.end) {
            final total = math.max(1, range.word.endMs - range.word.startMs);
            final progress =
                ((playbackMs - range.word.startMs) / total).clamp(0.0, 1.0);
            color = Color.lerp(
              Colors.white.withValues(alpha: .25),
              Colors.white,
              progress,
            );
            break;
          }
        }
      }
      spans.add(TextSpan(text: chars[i], style: base.copyWith(color: color)));
    }
    final body = Text.rich(TextSpan(children: spans));
    if (segment.reading == null || segment.reading!.isEmpty) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          segment.reading!,
          style: TextStyle(
            color: Colors.white.withValues(alpha: current ? .68 : .30),
            fontSize: (current ? 11 : 9) * fontScale,
          ),
        ),
        body,
      ],
    );
  }
}

class _ImmersiveModeContent extends StatelessWidget {
  final bool compact;
  final Track track;
  final PlayerController player;
  final bool showLyrics;
  final ParsedLyrics? lyrics;
  final bool lyricLoading;
  final bool lyricFailed;
  final VoidCallback onRetryLyrics;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;

  const _ImmersiveModeContent(
      {required this.compact,
      required this.track,
      required this.player,
      required this.showLyrics,
      required this.lyrics,
      required this.lyricLoading,
      required this.lyricFailed,
      required this.onRetryLyrics,
      required this.onOpenArtist,
      required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return Row(
        children: [
          Expanded(
            child: _ArtworkMeta(
              track: track,
              player: player,
              lyrics: lyrics,
              cropArtwork: true,
              sizeFactor: .60,
              onOpenArtist: onOpenArtist,
              onOpenAlbum: onOpenAlbum,
            ),
          ),
          const SizedBox(width: 34),
          Expanded(
            child: _LyricsSide(
              lyrics: lyrics,
              player: player,
              loading: lyricLoading,
              failed: lyricFailed,
              onRetry: onRetryLyrics,
              immersive: true,
            ),
          ),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: showLyrics
          ? _LyricsSide(
              key: const ValueKey('lyrics'),
              lyrics: lyrics,
              player: player,
              loading: lyricLoading,
              failed: lyricFailed,
              onRetry: onRetryLyrics)
          : SingleChildScrollView(
              key: const ValueKey('art'),
              physics: const BouncingScrollPhysics(),
              child: _ArtworkMeta(
                track: track,
                player: player,
                lyrics: lyrics,
                cropArtwork: true,
                sizeFactor: .58,
                onOpenArtist: onOpenArtist,
                onOpenAlbum: onOpenAlbum,
              ),
            ),
    );
  }
}

class _MinimalModeContent extends StatelessWidget {
  final bool compact;
  final Track track;
  final PlayerController player;
  final bool showLyrics;
  final ParsedLyrics? lyrics;
  final VoidCallback onToggleLyrics;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;

  const _MinimalModeContent(
      {required this.compact,
      required this.track,
      required this.player,
      required this.showLyrics,
      required this.lyrics,
      required this.onToggleLyrics,
      required this.onOpenArtist,
      required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    if (showLyrics) {
      return _LyricsSide(
          lyrics: lyrics,
          player: player,
          loading: false,
          failed: false,
          onRetry: onToggleLyrics);
    }
    if (!compact) {
      return Row(
        children: [
          Expanded(
            child: _ArtworkMeta(
              track: track,
              player: player,
              sizeFactor: .56,
              onOpenArtist: onOpenArtist,
              onOpenAlbum: onOpenAlbum,
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: _LyricsSide(
              lyrics: lyrics,
              player: player,
              loading: false,
              failed: false,
              onRetry: onToggleLyrics,
            ),
          ),
        ],
      );
    }
    const art = 220.0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onToggleLyrics,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Artwork(
                url: track.album.picUrl,
                size: art,
                radius: 18,
                shadow: true,
                border: false,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _TrackMeta(
              track: track,
              onOpenArtist: onOpenArtist,
              onOpenAlbum: onOpenAlbum),
          const SizedBox(height: 6),
          _LyricPreview(lyrics: lyrics, player: player),
        ],
      ),
    );
  }
}

class _ArtworkMeta extends StatelessWidget {
  final Track track;
  final PlayerController? player;
  final ParsedLyrics? lyrics;
  final bool cropArtwork;
  final double sizeFactor;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;

  const _ArtworkMeta(
      {required this.track,
      this.player,
      this.lyrics,
      this.cropArtwork = false,
      required this.sizeFactor,
      required this.onOpenArtist,
      required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(
            500.0, math.min(c.maxWidth * .78, c.maxHeight * sizeFactor));
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Artwork(
                  url: track.album.picUrl,
                  size: math.max(180, size),
                  radius: 22,
                  shadow: true,
                  border: false,
                  scale: cropArtwork ? 1.11 : 1.0,
                ),
              ),
              const SizedBox(height: 18),
              _TrackMeta(
                  track: track,
                  onOpenArtist: onOpenArtist,
                  onOpenAlbum: onOpenAlbum),
              if (player != null && lyrics != null) ...[
                const SizedBox(height: 8),
                _LyricPreview(lyrics: lyrics, player: player!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TrackMeta extends StatelessWidget {
  final Track track;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;
  const _TrackMeta(
      {required this.track,
      required this.onOpenArtist,
      required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MarqueeText(track.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        AutoScrollMetadata(
            identity: '${track.id}:${track.artistNames}:${track.album.name}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...track.artists.asMap().entries.expand((entry) {
                  final out = <Widget>[];
                  if (entry.key > 0) {
                    out.add(const Text(' / ',
                        style: TextStyle(color: Colors.white54)));
                  }
                  out.add(InkWell(
                    onTap: () => onOpenArtist(entry.value),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      child: Text(entry.value.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none)),
                    ),
                  ));
                  return out;
                }),
                if (track.album.id > 0 && track.album.name.isNotEmpty) ...[
                  const Text(' · ', style: TextStyle(color: Colors.white54)),
                  InkWell(
                    onTap: () => onOpenAlbum(track.album),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      child: Text(track.album.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none)),
                    ),
                  ),
                ],
              ],
            )),
      ],
    );
  }
}

class _LyricPreview extends StatelessWidget {
  final ParsedLyrics? lyrics;
  final PlayerController player;
  const _LyricPreview({required this.lyrics, required this.player});

  @override
  Widget build(BuildContext context) {
    if (lyrics == null || lyrics!.lines.isEmpty) {
      return const SizedBox(height: 34);
    }
    final active = lyrics!.activeIndex(player.position) ?? 0;
    final current = lyrics!.lines[active].text.trim();
    final next = active + 1 < lyrics!.lines.length
        ? lyrics!.lines[active + 1].text.trim()
        : '';
    return SizedBox(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (current.isNotEmpty)
            Text(current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          if (next.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(next,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12))),
        ],
      ),
    );
  }
}

class _LyricsSide extends StatefulWidget {
  final ParsedLyrics? lyrics;
  final PlayerController player;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;
  final bool immersive;

  const _LyricsSide(
      {super.key,
      required this.lyrics,
      required this.player,
      required this.loading,
      required this.failed,
      required this.onRetry,
      this.immersive = false});

  @override
  State<_LyricsSide> createState() => _LyricsSideState();
}

class _LyricsSideState extends State<_LyricsSide> {
  final ScrollController controller = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int? lastActive;
  bool _userScrolling = false;
  bool _scrollScheduled = false;
  Timer? _browseTimer;

  @override
  void dispose() {
    _browseTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) => _lineKeys.putIfAbsent(index, GlobalKey.new);

  void _scheduleScrollToActive(int active) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || _userScrolling) return;
      final target = _lineKeys[active]?.currentContext;
      if (target == null) return;
      final jump = lastActive != null && (active - lastActive!).abs() > 6;
      lastActive = active;
      Scrollable.ensureVisible(
        target,
        alignment: .34,
        duration: jump ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.lyrics;
    if (parsed == null) {
      if (widget.loading) {
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.failed ? Icons.refresh_rounded : Icons.lyrics_outlined,
                color: Colors.white60, size: 34),
            const SizedBox(height: 10),
            Text(widget.failed ? '歌词加载失败' : '暂无歌词',
                style: const TextStyle(color: Colors.white70)),
            if (widget.failed)
              TextButton(onPressed: widget.onRetry, child: const Text('重新加载')),
          ],
        ),
      );
    }
    if (parsed.lines.isEmpty) {
      return Center(
        child: Text(
          parsed.instrumental ? '纯音乐，请欣赏' : '暂无歌词',
          style: const TextStyle(color: Colors.white60),
        ),
      );
    }

    final active = parsed.activeIndex(widget.player.position) ?? 0;
    _scheduleScrollToActive(active);
    final settings = context.watch<SettingsStore>();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _browseTimer?.cancel();
          setState(() => _userScrolling = true);
        } else if (notification is ScrollEndNotification && _userScrolling) {
          _browseTimer?.cancel();
          _browseTimer = Timer(const Duration(seconds: 1), () {
            if (mounted) setState(() => _userScrolling = false);
          });
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(14, 44, 14, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < parsed.lines.length; i++)
              GestureDetector(
                key: _keyFor(i),
                onTap: () {
                  // Invalidate the old anchor before seeking. The PlayerController
                  // publishes the new position immediately, and the next frame
                  // will ensureVisible() the newly active line even for a large
                  // backward jump (e.g. 3:39 -> 0:26).
                  lastActive = null;
                  _userScrolling = false;
                  unawaited(widget.player.seek(
                    Duration(milliseconds: parsed.lines[i].startMs),
                  ));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),

                  child: LyricDistanceBlur(
                    radius: lyricBlurRadius(
                        i, active, settings.lyricBlur, _userScrolling),
                    child: _LyricLineView(
                      line: parsed.lines[i],
                      current: i == active,
                      settings: settings,
                      playbackMs: widget.player.position.inMilliseconds,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LyricLineView extends StatelessWidget {
  final LyricLine line;
  final bool current;
  final SettingsStore settings;
  final int playbackMs;
  const _LyricLineView(
      {required this.line,
      required this.current,
      required this.settings,
      required this.playbackMs});

  @override
  Widget build(BuildContext context) {
    final main = _mainLyricText();
    final children = <Widget>[];
    if (settings.annotation == LyricsAnnotationMode.romaji &&
        line.romaji?.trim().isNotEmpty == true) {
      children.add(Text(line.romaji!,
          style: TextStyle(
              color: Colors.white.withValues(alpha: current ? .70 : .32),
              fontSize: (current ? 13 : 11) * settings.lyricFontScale,
              fontWeight: FontWeight.w500)));
      children.add(const SizedBox(height: 3));
    }
    children.add(main);
    if (settings.translation && line.translation?.trim().isNotEmpty == true) {
      children.add(const SizedBox(height: 4));
      children.add(Text(line.translation!,
          style: TextStyle(
              color: Colors.white.withValues(alpha: current ? .62 : .28),
              fontSize: (current ? 13 : 11) * settings.lyricFontScale)));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _mainLyricText() {
    if (settings.annotation == LyricsAnnotationMode.furigana &&
        line.furigana.isNotEmpty) {
      final wordRanges = <_WordCharRange>[];
      var cursor = 0;
      for (final word in line.words) {
        final length = word.text.characters.length;
        wordRanges.add(_WordCharRange(cursor, cursor + length, word));
        cursor += length;
      }
      var absoluteCursor = 0;
      final widgets = <Widget>[];
      for (final seg in line.furigana) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(right: 1),
          child: _FuriganaSegmentView(
            segment: seg,
            current: current,
            playbackMs: playbackMs,
            absoluteStart: absoluteCursor,
            wordRanges: wordRanges,
            fontScale: settings.lyricFontScale,
          ),
        ));
        absoluteCursor += seg.text.characters.length;
      }
      return Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 0,
          runSpacing: 3,
          children: widgets);
    }
    if (current && settings.verbatim && line.words.isNotEmpty) {
      return _KaraokeLineText(line: line, playbackMs: playbackMs,
          fontSize: 23 * settings.lyricFontScale);
    }
    return Text(
      line.text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: current ? 1 : .40),
        fontSize: (current ? 23 : 16) * settings.lyricFontScale,
        height: 1.3,
        fontWeight: current ? FontWeight.w800 : FontWeight.w500,
      ),
    );
  }
}

class _WordCharRange {
  final int start;
  final int end;
  final LyricWord word;
  const _WordCharRange(this.start, this.end, this.word);
}

class _KaraokeLineText extends StatelessWidget {
  final LyricLine line;
  final int playbackMs;
  final double fontSize;
  const _KaraokeLineText(
      {required this.line, required this.playbackMs, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final glowEnabled = context.watch<SettingsStore>().cjkGlow &&
        !MediaQuery.disableAnimationsOf(context);
    for (final word in line.words) {
      final wordProgress =
          ((playbackMs - word.startMs) / math.max(1, word.endMs - word.startMs))
              .clamp(0.0, 1.0);
      final glow =
          glowEnabled && cjkLongNote(word.text, word.endMs - word.startMs)
              ? math.sin(wordProgress * math.pi)
              : 0.0;
      final chars = word.text.characters.toList();
      final total = math.max(1, word.endMs - word.startMs);
      for (var i = 0; i < chars.length; i++) {
        final start = word.startMs + (total * i / chars.length).round();
        final end = word.startMs + (total * (i + 1) / chars.length).round();
        final progress =
            ((playbackMs - start) / math.max(1, end - start)).clamp(0.0, 1.0);
        final color = Color.lerp(
          Colors.white.withValues(alpha: .25),
          Colors.white,
          progress,
        );
        spans.add(TextSpan(
          text: chars[i],
          style: TextStyle(
            color: color,
            shadows: glow > .01
                ? [
                    Shadow(
                        color: Colors.white.withValues(alpha: glow * .75),
                        blurRadius: 12 * glow)
                  ]
                : null,
            fontSize: fontSize,
            height: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ));
      }
    }
    return Text.rich(TextSpan(children: spans), softWrap: true);
  }
}

class _FuriganaSegmentView extends StatelessWidget {
  final FuriganaSegment segment;
  final bool current;
  final int playbackMs;
  final int absoluteStart;
  final List<_WordCharRange> wordRanges;
  final double fontScale;

  const _FuriganaSegmentView(
      {required this.segment,
      required this.current,
      required this.playbackMs,
      required this.absoluteStart,
      required this.wordRanges,
      required this.fontScale});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
        color: Colors.white.withValues(alpha: current ? 1 : .4),
        fontSize: (current ? 23 : 16) * fontScale,
        height: 1.2,
        fontWeight: current ? FontWeight.w800 : FontWeight.w500);
    final spans = <TextSpan>[];
    final chars = segment.text.characters.toList();
    for (var i = 0; i < chars.length; i++) {
      final absolute = absoluteStart + i;
      var color = base.color;
      if (current &&
          context.read<SettingsStore>().verbatim &&
          wordRanges.isNotEmpty) {
        for (final range in wordRanges) {
          if (absolute >= range.start && absolute < range.end) {
            final total = math.max(1, range.word.endMs - range.word.startMs);
            final progress =
                ((playbackMs - range.word.startMs) / total).clamp(0.0, 1.0);
            color = Color.lerp(
                Colors.white.withValues(alpha: .25), Colors.white, progress);
            break;
          }
        }
      }
      spans.add(TextSpan(text: chars[i], style: base.copyWith(color: color)));
    }
    final body = Text.rich(TextSpan(children: spans));
    if (segment.reading == null || segment.reading!.isEmpty) return body;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(segment.reading!,
          style: TextStyle(
              color: Colors.white.withValues(alpha: current ? .65 : .28),
              fontSize: (current ? 9 : 7) * fontScale)),
      body
    ]);
  }
}

class _PlaybackControls extends StatelessWidget {
  final Track track;
  final PlayerController player;
  final VoidCallback onQueue;
  final bool showVolume;
  final bool minimal;
  final bool immersive;
  final bool dualPane;
  final bool queueSelected;
  final double timelineOffset;
  final bool showLyrics;
  final VoidCallback onToggleLyrics;

  const _PlaybackControls({
    required this.track,
    required this.player,
    required this.onQueue,
    this.showVolume = false,
    this.minimal = false,
    this.immersive = false,
    this.dualPane = false,
    this.queueSelected = false,
    this.timelineOffset = -8,
    this.showLyrics = false,
    required this.onToggleLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = player.duration.inMilliseconds > 0
        ? player.duration.inMilliseconds
        : track.durationMs;
    final value =
        player.position.inMilliseconds.clamp(0, math.max(1, maxMs)).toDouble();
    final liked = context.watch<AccountStore>().liked(track.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;
        if (minimal) {
          return _MinimalPlaybackControls(
            track: track,
            player: player,
            onQueue: onQueue,
            showVolume: showVolume,
            maxMs: maxMs,
            value: value,
            narrow: narrow,
            compactHeight: dualPane,
            queueSelected: queueSelected,
            showHeart: dualPane,
          );
        }

        final controlHeight = narrow ? 240.0 : 256.0;
        final transportIcon = narrow ? 38.0 : 41.0;
        final transportHit = narrow ? 56.0 : 62.0;
        final playIcon = narrow ? 46.0 : 50.0;
        final playHit = narrow ? 72.0 : 80.0;
        final secondaryIcon = narrow ? 21.0 : 23.0;
        final secondaryHit = narrow ? 52.0 : 56.0;
        final volumeWidth = math.min(320.0, constraints.maxWidth);
        // 4px outer padding + 17px speaker + 7px gap at each end.
        final volumeTrackWidth = volumeWidth - 56;
        final transportRowWidth = math.min(constraints.maxWidth,
            volumeTrackWidth + transportHit - transportIcon);

        return SizedBox(
          height: controlHeight,
          child: Column(
            children: [
              Transform.translate(
                offset: Offset(0, dualPane ? -8 : timelineOffset),
                child: _Timeline(
                  player: player,
                  maxMs: maxMs,
                  value: value,
                  horizontalPadding: 0,
                ),
              ),
              const SizedBox(height: 14),
              Transform.translate(
                offset: Offset(0, dualPane ? 0 : timelineOffset / 2 - 4),
                child: SizedBox(width: transportRowWidth, child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ControlIcon(
                    icon: CupertinoIcons.backward_fill,
                    size: transportIcon,
                    buttonSize: transportHit,
                    onTap: player.previous,
                    label: '上一首',
                  ),
                  _ControlIcon(
                    icon: player.isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: playIcon,
                    buttonSize: playHit,
                    onTap: player.toggle,
                    label: player.isPlaying ? '暂停' : '播放',
                  ),
                  _ControlIcon(
                    icon: CupertinoIcons.forward_fill,
                    size: transportIcon,
                    buttonSize: transportHit,
                    onTap: player.next,
                    label: '下一首',
                  ),
                ],
              ))),
              if (showVolume) ...[
                const SizedBox(height: 10),
                _VolumeControlBar(
                  player: player,
                  width: math.min(320, constraints.maxWidth),
                ),
              ],
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: math.min(330, constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ControlIcon(
                        // Immersive mode uses one shared lyrics/cover toggle icon.
                        // The selected state is communicated by the active accent color:
                        // white in cover mode, accent when lyrics are shown.
                        icon: immersive
                            ? CupertinoIcons.quote_bubble_fill
                            : (liked
                                ? CupertinoIcons.heart_fill
                                : CupertinoIcons.heart),
                        size: secondaryIcon,
                        buttonSize: secondaryHit,
                        active: immersive ? showLyrics : liked,
                        circleBackground: true,
                        onTap: immersive
                            ? onToggleLyrics
                            : () async {
                                try {
                                  await context
                                      .read<AccountStore>()
                                      .toggleLike(track.id);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                }
                              },
                        label: immersive
                            ? (showLyrics ? '显示封面' : '显示歌词')
                            : (liked ? '取消喜欢' : '喜欢'),
                      ),
                      _ControlIcon(
                        icon: player.playbackModeIcon,
                        size: secondaryIcon,
                        buttonSize: secondaryHit,
                        active: player.shuffle ||
                            player.repeatMode == AudioServiceRepeatMode.one,
                        circleBackground: true,
                        onTap: player.cyclePlaybackMode,
                        label: player.playbackModeLabel,
                      ),
                      _ControlIcon(
                        icon: CupertinoIcons.list_bullet,
                        size: secondaryIcon,
                        buttonSize: secondaryHit,
                        circleBackground: false,
                        active: queueSelected,
                        onTap: onQueue,
                        label: '播放队列',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MinimalPlaybackControls extends StatelessWidget {
  final Track track;
  final PlayerController player;
  final VoidCallback onQueue;
  final bool showVolume;
  final int maxMs;
  final double value;
  final bool narrow;
  final bool compactHeight;
  final bool queueSelected;
  final bool showHeart;

  const _MinimalPlaybackControls({
    required this.track,
    required this.player,
    required this.onQueue,
    required this.showVolume,
    required this.maxMs,
    required this.value,
    required this.narrow,
    this.compactHeight = false,
    this.queueSelected = false,
    this.showHeart = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = narrow ? 27.0 : 29.0;
    final hit = narrow ? 50.0 : 54.0;
    final play = narrow ? 38.0 : 42.0;
    final gap = narrow ? 5.0 : 9.0;

    return SizedBox(
      height: compactHeight ? (showVolume ? 180 : 128) : (narrow ? 244 : 256),
      child: Column(
        children: [
          Transform.translate(
            offset: Offset(0, compactHeight ? -8 : 12),
            child: _Timeline(
              player: player,
              maxMs: maxMs,
              value: value,
              horizontalPadding: 0,
            ),
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
            width: math.min(380, MediaQuery.sizeOf(context).width),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showHeart) _ControlIcon(
                  icon: context.watch<AccountStore>().liked(track.id)
                      ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                  active: context.watch<AccountStore>().liked(track.id),
                  size: icon, buttonSize: hit, label: '喜欢',
                  onTap: () async {
                    final account = context.read<AccountStore>();
                    final liked = account.liked(track.id);
                    try { await account.toggleLike(track.id);
                      player.showNotice(liked ? '已取消喜欢' : '已加入喜欢');
                    } catch (e) { player.showNotice('$e'); }
                  }),
                _ControlIcon(
                  icon: CupertinoIcons.list_bullet,
                  size: icon,
                  buttonSize: hit,
                  onTap: onQueue,
                  active: queueSelected,
                  label: '播放队列',
                ),
                SizedBox(width: gap),
                _ControlIcon(
                  icon: CupertinoIcons.backward_fill,
                  size: icon,
                  buttonSize: hit,
                  onTap: player.previous,
                  label: '上一首',
                ),
                SizedBox(width: gap + 2),
                _ControlIcon(
                  icon: player.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: play,
                  buttonSize: hit + 8,
                  onTap: player.toggle,
                  label: player.isPlaying ? '暂停' : '播放',
                ),
                SizedBox(width: gap + 2),
                _ControlIcon(
                  icon: CupertinoIcons.forward_fill,
                  size: icon,
                  buttonSize: hit,
                  onTap: player.next,
                  label: '下一首',
                ),
                SizedBox(width: gap),
                _ControlIcon(
                  icon: player.playbackModeIcon,
                  size: icon,
                  buttonSize: hit,
                  active: player.shuffle ||
                      player.repeatMode == AudioServiceRepeatMode.one,
                  onTap: player.cyclePlaybackMode,
                  label: player.playbackModeLabel,
                ),
              ],
            ),
          )),
          if (showVolume) ...[
            const SizedBox(height: 8),
            _VolumeControlBar(
              player: player,
              width: math.min(320, MediaQuery.sizeOf(context).width - 8),
            ),
          ],
        ],
      ),
    );
  }
}

class _FullWidthSliderTrackShape extends RoundedRectSliderTrackShape {
  const _FullWidthSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }
}

class _Timeline extends StatefulWidget {
  final PlayerController player;
  final int maxMs;
  final double value;
  final double horizontalPadding;

  const _Timeline({
    required this.player,
    required this.maxMs,
    required this.value,
    this.horizontalPadding = 22,
  });

  @override State<_Timeline> createState() => _TimelineState();
}
class _TimelineState extends State<_Timeline> {
  double? dragValue;
  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final horizontalPadding = widget.horizontalPadding;
    final maxMs = widget.maxMs;

    final end = player.duration.inMilliseconds > 0
        ? player.duration
        : player.currentTrack?.duration ?? const Duration();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              trackShape: const _FullWidthSliderTrackShape(),
              activeTrackColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              thumbShape: SliderComponentShape.noThumb,
              overlayColor: Colors.white.withValues(alpha: .10),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: SizedBox(height: 36, child: Slider(
                    value: (dragValue ?? widget.value).clamp(0, math.max(1, maxMs)).toDouble(),
                    max: math.max(1, maxMs).toDouble(),
                    onChangeStart: (v) => setState(() => dragValue = v),
                    onChanged: (v) => setState(() => dragValue = v),
                    onChangeEnd: (v) async {
                      try { await player.seek(Duration(milliseconds: v.round())); }
                      catch (_) { player.showNotice('调整播放进度失败'); }
                      finally { if (mounted) setState(() => dragValue = null); }
                    },
                  )),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(dragValue == null ? player.position :
                    Duration(milliseconds: dragValue!.round())),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              Text(
                formatDuration(end),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VolumeControlBar extends StatelessWidget {
  final PlayerController player;
  final double width;

  const _VolumeControlBar({
    required this.player,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final value = player.volume.clamp(0.0, 1.0).toDouble();
    return Container(
      width: width,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.speaker_1_fill,
            color: Colors.white,
            size: 17,
            shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                trackShape: const _FullWidthSliderTrackShape(),
                padding: EdgeInsets.zero,
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: SliderComponentShape.noThumb,
                overlayColor: Colors.white.withValues(alpha: .10),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                      value: value,
                      min: 0,
                      max: 1,
                      onChanged: (next) => player.volume = next,
                    ),
            ),
          ),
          const SizedBox(width: 7),
          const Icon(
            CupertinoIcons.speaker_3_fill,
            color: Colors.white,
            size: 17,
            shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ],
      ),
    );
  }
}

class _ControlIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final double buttonSize;
  final bool active;
  final bool circleBackground;
  final VoidCallback onTap;
  final String? label;

  const _ControlIcon({
    required this.icon,
    required this.onTap,
    this.size = 27,
    this.buttonSize = 48,
    this.active = false,
    this.circleBackground = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isHeart = icon == CupertinoIcons.heart_fill || icon == CupertinoIcons.heart;
    final iconColor = active
        ? (isHeart ? AppAccent.appleRed.color : const Color(0xFFFF5A66))
        : Colors.white;
    const background = Colors.transparent;

    final child = Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: .10),
        highlightColor: Colors.white.withValues(alpha: .06),
        onTap: onTap,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Center(
            child: Icon(
              icon,
              color: iconColor,
              size: size,
              shadows: isHeart ? const [] : const [
                Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );

    return label == null ? child : Tooltip(message: label!, child: child);
  }
}

class _PlayerDismissHandle extends StatefulWidget {
  final VoidCallback onClose;
  const _PlayerDismissHandle({required this.onClose});
  @override State<_PlayerDismissHandle> createState() => _PlayerDismissHandleState();
}
class _PlayerDismissHandleState extends State<_PlayerDismissHandle> {
  double distance = 0;
  @override
  Widget build(BuildContext context) => Semantics(label: '下拉关闭播放页',
    button: true, onTap: widget.onClose,
    child: GestureDetector(behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => distance = 0,
      onVerticalDragUpdate: (details) => distance += details.delta.dy,
      onVerticalDragEnd: (details) {
        if (distance > 44 || (distance > 8 && (details.primaryVelocity ?? 0) > 600)) {
          widget.onClose();
        }
        distance = 0;
      },
      child: SizedBox(height: 28, width: double.infinity,
        child: Center(child: Container(width: 44, height: 4,
          decoration: BoxDecoration(color: Colors.white70,
            borderRadius: BorderRadius.circular(4)))))));
}
class _MobilePlayerHeading extends StatelessWidget {
  final Track track;
  final bool showCover;
  final bool externalCover;
  final Duration duration;
  final VoidCallback? onCoverTap;
  final ValueChanged<ArtistRef> onOpenArtist;
  final ValueChanged<AlbumRef> onOpenAlbum;
  const _MobilePlayerHeading({required this.track, required this.onOpenArtist,
    required this.onOpenAlbum, this.showCover = false, this.externalCover = false,
    this.duration = const Duration(milliseconds: 420), this.onCoverTap});
  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountStore>();
    final liked = account.liked(track.id);
    return Row(children: [
      Expanded(child: Row(children: [
        AnimatedContainer(duration: duration, curve: Curves.easeInOutCubic,
          width: showCover ? 75 : 0,
          child: externalCover ? null : (showCover ? GestureDetector(
            onTap: onCoverTap, child: Artwork(url: track.album.picUrl,
              size: 62, radius: 12, shadow: false, border: false)) : null)),
        Expanded(child: _ImmersiveMetadata(track: track,
          onOpenArtist: onOpenArtist, onOpenAlbum: onOpenAlbum)),
      ])),
      const SizedBox(width: 6),
      Transform.translate(offset: const Offset(0, -2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
      _RoundGlassButton(iconSize: 26, hitSize: 44, icon: liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
        active: liked, tooltip: liked ? '取消喜欢' : '喜欢', onTap: () async {
          final player = context.read<PlayerController>();
          try { await account.toggleLike(track.id);
            player.showNotice(liked ? '已取消喜欢' : '已加入喜欢');
          } catch (e) { player.showNotice('$e'); }
        }),
      const SizedBox(width: 4),
      TrackActionMenu(track: track, glassMenu: true, plainPlayerButton: true,
        playerButtonSize: 44, playerIconSize: 26,
        onOpenArtist: onOpenArtist, onOpenAlbum: onOpenAlbum),
      ])),
    ]);
  }
}

@visibleForTesting
Widget kumonePlayerPortraitForTest({required Track track,
  required PlayerController player, ParsedLyrics? lyrics,
  bool showLyrics = false, bool minimal = false, VoidCallback? onClose}) =>
  LayoutBuilder(builder: (context, bounds) => Column(children: [
    _PlayerDismissHandle(onClose: onClose ?? () {}),
    Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 36),
      child: _ImmersiveMobileContent(track: track, player: player,
        minimal: minimal, showLyrics: showLyrics, lyrics: lyrics,
        lyricLoading: false, lyricFailed: false, onRetryLyrics: () {},
        onOpenArtist: (_) {}, onOpenAlbum: (_) {}, onToggleLyrics: () {}))),
    Padding(padding: const EdgeInsets.fromLTRB(36, 6, 36, 10),
      child: _PlaybackControls(track: track, player: player, onQueue: () {},
        timelineOffset: _portraitTimelineOffset(bounds.maxWidth - 72,
          bounds.maxHeight - 28 - ((bounds.maxWidth - 72) < 340 ? 240 : 256) - 16,
          minimal),
        showVolume: true, immersive: true, showLyrics: showLyrics,
        onToggleLyrics: () {})),
  ]));

class _PlayerDragDismiss extends StatefulWidget {
  final Widget child;
  const _PlayerDragDismiss({required this.child});
  @override State<_PlayerDragDismiss> createState() => _PlayerDragDismissState();
}
class _PlayerDragDismissState extends State<_PlayerDragDismiss>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 220));
  double offset = 0, from = 0, target = 0;
  bool completing = false;
  @override void initState() {
    super.initState();
    animation.addListener(() {
      setState(() => offset = from + (target - from) * Curves.easeOutCubic.transform(animation.value));
    });
  }
  Future<void> finish(double velocity) async {
    if (completing) return;
    final dismiss = offset > 44 || (offset > 8 && velocity > 600);
    completing = true;
    from = offset;
    target = dismiss ? MediaQuery.sizeOf(context).height : 0;
    await animation.forward(from: 0);
    if (!mounted) return;
    if (dismiss) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) Navigator.of(context).removeRoute(route);
    } else { completing = false; }
  }
  @override Widget build(BuildContext context) => Stack(children: [
    Transform.translate(offset: Offset(0, offset), child: widget.child),
    Positioned(top: MediaQuery.paddingOf(context).top, left: 0, right: 0,
      height: 44,
      child: GestureDetector(behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) { animation.stop(); completing = false; },
        onVerticalDragUpdate: (details) {
          if (!completing) setState(() => offset = (offset + details.delta.dy).clamp(0, MediaQuery.sizeOf(context).height));
        },
        onVerticalDragEnd: (details) => finish(details.primaryVelocity ?? 0),
        onVerticalDragCancel: () => finish(0))),
  ]);
  @override void dispose() { animation.dispose(); super.dispose(); }
}

// Match the existing cover-to-preview gap with the three-row preview-to-track
// gap. Row geometry includes the 2px padding on each lyric line. Two-row
// previews keep this exact same anchor and never recalculate the timeline.
double _portraitTimelineOffset(double width, double contentHeight, bool minimal) {
  if (minimal) return -8;
  const heading = 68.0;
  final available = math.max(0.0, contentHeight - heading);
  final cover = math.min(math.min(340.0, math.min(width * .80, contentHeight * .56)),
      math.max(24.0, available - 109));
  final extra = math.max(0.0, available - 109 - cover);
  final coverBottom = heading + 12 + extra / 2 + cover;
  final firstRowTop = contentHeight - 88 + 2;
  final gap = math.max(0.0, firstRowTop - coverBottom);
  // Full three-row text ends at preview top + 67.6; the Slider track center
  // starts 24px below the content, before this translation (track is 5px).
  return math.max(-8.0, gap - 41.9);
}
