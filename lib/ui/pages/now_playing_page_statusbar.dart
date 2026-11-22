import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/models/lyrics.dart';
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

  // The player page paints its ambient background behind the Android system
  // bars. Keep the status-bar icon contrast adaptive to the current artwork.
  ImageStream? _statusArtworkStream;
  ImageStreamListener? _statusArtworkListener;
  int? _statusArtworkId;
  bool _statusUseDarkIcons = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = context.read<PlayerController>();
    final settings = context.read<SettingsStore>();
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

  void _sampleStatusBarArtwork(Track track) {
    if (_statusArtworkId == track.id) return;
    _statusArtworkId = track.id;

    final oldStream = _statusArtworkStream;
    final oldListener = _statusArtworkListener;
    if (oldStream != null && oldListener != null) {
      oldStream.removeListener(oldListener);
    }

    final url = track.album.picUrl;
    if (url == null || url.isEmpty) {
      if (mounted && _statusUseDarkIcons) {
        setState(() => _statusUseDarkIcons = false);
      }
      _statusArtworkStream = null;
      _statusArtworkListener = null;
      return;
    }

    final provider = ResizeImage(
      NetworkImage(resizedImageUrl(url, 64)),
      width: 64,
      height: 64,
    );
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((imageInfo, _) async {
      try {
        final data = await imageInfo.image.toByteData(
          format: ImageByteFormat.rawRgba,
        );
        if (!mounted || data == null || _statusArtworkId != track.id) return;

        final bytes = data.buffer.asUint8List();
        final width = imageInfo.image.width;
        final height = imageInfo.image.height;
        if (width <= 0 || height <= 0 || bytes.length < width * height * 4) {
          return;
        }

        // The ambient background is blurred and darkened by the player page,
        // so use the upper part of the artwork and a conservative threshold.
        double sum = 0;
        var count = 0;
        final sampleBottom = (height * .35).round().clamp(1, height);
        for (var y = 0; y < sampleBottom; y += 2) {
          for (var x = 0; x < width; x += 2) {
            final i = (y * width + x) * 4;
            final r = bytes[i];
            final g = bytes[i + 1];
            final b = bytes[i + 2];
            sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            count++;
          }
        }
        if (count == 0) return;

        final luma = sum / count;
        // Only switch to dark Android status-bar icons when the artwork is
        // genuinely bright; otherwise white icons are safer on the darkened
        // ambient background used by the player.
        final useDark = luma >= .68;
        if (mounted && _statusArtworkId == track.id &&
            _statusUseDarkIcons != useDark) {
          setState(() => _statusUseDarkIcons = useDark);
        }
      } catch (_) {
        if (mounted && _statusArtworkId == track.id && _statusUseDarkIcons) {
          setState(() => _statusUseDarkIcons = false);
        }
      }
    });
    stream.addListener(listener);
    _statusArtworkStream = stream;
    _statusArtworkListener = listener;
  }

  @override
  void dispose() {
    final stream = _statusArtworkStream;
    final listener = _statusArtworkListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    super.dispose();
  }

  void _openQueue() {
    if (MediaQuery.sizeOf(context).width >= 840) {
      setState(() => showQueue = !showQueue);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .48),
      builder: (_) => const QueuePage(),
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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final settings = context.watch<SettingsStore>();
    final track = player.currentTrack;
    if (track == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text('暂无播放')));
    }
    if (loadedId != track.id && !lyricLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(track);
      });
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_statusArtworkId != track.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _statusArtworkId != track.id) {
          _sampleStatusBarArtwork(track);
        }
      });
    }

    final statusIconBrightness =
        _statusUseDarkIcons ? Brightness.dark : Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // Transparent + edge-to-edge lets the ambient artwork/gradient continue
        // underneath the Android status bar instead of leaving a separate
        // white/light strip above the player.
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: statusIconBrightness,
        statusBarBrightness: _statusUseDarkIcons
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: statusIconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
        fit: StackFit.expand,
        children: [
          if (settings.ambient && track.album.picUrl?.isNotEmpty == true)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                child: Opacity(
                  opacity: (.38 + settings.ambientIntensity * .10).clamp(.28, .55),
                  child: Image.network(
                    resizedImageUrl(track.album.picUrl, 1000),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [Colors.black.withValues(alpha: .18), Colors.black.withValues(alpha: .78)]
                      : [Colors.black.withValues(alpha: .30), Colors.black.withValues(alpha: .82)],
                ),
              ),
            ),
          ),
          // A very light top scrim keeps system-bar glyphs readable without
          // introducing a solid status-bar strip. The actual color still comes
          // from the same ambient background painted underneath.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top + 34,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _statusUseDarkIcons
                        ? [
                            Colors.white.withValues(alpha: .06),
                            Colors.transparent,
                          ]
                        : [
                            Colors.black.withValues(alpha: .14),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 840;
                return Column(
                  children: [
                    _TopChrome(
                      track: track,
                      showLyrics: showLyrics,
                      onClose: () => Navigator.pop(context),
                      onToggleLyrics: () => setState(() {
                        showLyrics = !showLyrics;
                        showQueue = false;
                      }),
                      onOpenAlbum: _openAlbum,
                      onOpenArtist: _openArtist,
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(compact ? 18 : 38, 2, compact ? 18 : 38, 0),
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
                          onToggleLyrics: () => setState(() => showLyrics = !showLyrics),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 16 : 44, 6, compact ? 16 : 44, compact ? 10 : 16),
                      child: _PlaybackControls(
                        track: track,
                        player: player,
                        onQueue: _openQueue,
                        showVolume: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  final Track track;
  final bool showLyrics;
  final VoidCallback onClose;
  final VoidCallback onToggleLyrics;
  final ValueChanged<AlbumRef> onOpenAlbum;
  final ValueChanged<ArtistRef> onOpenArtist;

  const _TopChrome({
    required this.track,
    required this.showLyrics,
    required this.onClose,
    required this.onToggleLyrics,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 4),
      child: Row(
        children: [
          _RoundGlassButton(icon: CupertinoIcons.chevron_down, onTap: onClose, tooltip: '关闭播放页'),
          const Spacer(),
          _RoundGlassButton(
            icon: showLyrics ? CupertinoIcons.music_albums : CupertinoIcons.quote_bubble_fill,
            onTap: onToggleLyrics,
            tooltip: showLyrics ? '显示封面' : '显示歌词',
          ),
          const SizedBox(width: 6),
          TrackActionMenu(
            track: track,
            onOpenAlbum: onOpenAlbum,
            onOpenArtist: onOpenArtist,
            glassMenu: true,
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
  const _RoundGlassButton({required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    final fill = isDark
        ? Colors.black.withValues(alpha: .22)
        : Colors.white.withValues(alpha: .70);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: foreground.withValues(alpha: .10),
          highlightColor: foreground.withValues(alpha: .06),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              color: foreground,
              size: 23,
              shadows: [
                Shadow(
                  color: (isDark ? Colors.black : Colors.white)
                      .withValues(alpha: .38),
                  blurRadius: 4,
                ),
              ],
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
  });

  @override
  Widget build(BuildContext context) {
    if (showQueue) return const QueueListPanel(embedded: true);
    switch (mode) {
      case NowPlayingMode.immersive:
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

  const _ImmersiveModeContent({required this.compact, required this.track, required this.player, required this.showLyrics, required this.lyrics, required this.lyricLoading, required this.lyricFailed, required this.onRetryLyrics, required this.onOpenArtist, required this.onOpenAlbum});

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
          ? _LyricsSide(key: const ValueKey('lyrics'), lyrics: lyrics, player: player, loading: lyricLoading, failed: lyricFailed, onRetry: onRetryLyrics)
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

  const _MinimalModeContent({required this.compact, required this.track, required this.player, required this.showLyrics, required this.lyrics, required this.onToggleLyrics, required this.onOpenArtist, required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    if (showLyrics) {
      return _LyricsSide(lyrics: lyrics, player: player, loading: false, failed: false, onRetry: onToggleLyrics);
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
          _TrackMeta(track: track, onOpenArtist: onOpenArtist, onOpenAlbum: onOpenAlbum),
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

  const _ArtworkMeta({required this.track, this.player, this.lyrics, this.cropArtwork = false, required this.sizeFactor, required this.onOpenArtist, required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(500.0, math.min(c.maxWidth * .78, c.maxHeight * sizeFactor));
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
              _TrackMeta(track: track, onOpenArtist: onOpenArtist, onOpenAlbum: onOpenAlbum),
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
  const _TrackMeta({required this.track, required this.onOpenArtist, required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(track.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            ...track.artists.asMap().entries.expand((entry) {
              final out = <Widget>[];
              if (entry.key > 0) out.add(const Text(' / ', style: TextStyle(color: Colors.white54)));
              out.add(InkWell(
                onTap: () => onOpenArtist(entry.value),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Text(entry.value.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Text(track.album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                ),
              ),
            ],
          ],
        ),
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
    if (lyrics == null || lyrics!.lines.isEmpty) return const SizedBox(height: 34);
    final active = lyrics!.activeIndex(player.position) ?? 0;
    final current = lyrics!.lines[active].text.trim();
    final next = active + 1 < lyrics!.lines.length ? lyrics!.lines[active + 1].text.trim() : '';
    return SizedBox(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (current.isNotEmpty) Text(current, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          if (next.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(next, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12))),
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

  const _LyricsSide({super.key, required this.lyrics, required this.player, required this.loading, required this.failed, required this.onRetry, this.immersive = false});

  @override
  State<_LyricsSide> createState() => _LyricsSideState();
}

class _LyricsSideState extends State<_LyricsSide> {
  final ScrollController controller = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int? lastActive;
  bool _userScrolling = false;
  bool _scrollScheduled = false;

  @override
  void dispose() {
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
        if (notification is ScrollStartNotification && notification.dragDetails != null) {
          _userScrolling = true;
        } else if (notification is ScrollEndNotification) {
          Future<void>.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _userScrolling = false;
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: i == active
                        ? Colors.white.withValues(alpha: .08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _LyricLineView(
                    line: parsed.lines[i],
                    current: i == active,
                    settings: settings,
                    playbackMs: widget.player.position.inMilliseconds,
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
  const _LyricLineView({required this.line, required this.current, required this.settings, required this.playbackMs});

  @override
  Widget build(BuildContext context) {
    final main = _mainLyricText();
    final children = <Widget>[];
    if (settings.annotation == LyricsAnnotationMode.romaji && line.romaji?.trim().isNotEmpty == true) {
      children.add(Text(line.romaji!, style: TextStyle(color: Colors.white.withValues(alpha: current ? .70 : .32), fontSize: current ? 13 : 11, fontWeight: FontWeight.w500)));
      children.add(const SizedBox(height: 3));
    }
    children.add(main);
    if (settings.translation && line.translation?.trim().isNotEmpty == true) {
      children.add(const SizedBox(height: 4));
      children.add(Text(line.translation!, style: TextStyle(color: Colors.white.withValues(alpha: current ? .62 : .28), fontSize: current ? 13 : 11)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _mainLyricText() {
    if (settings.annotation == LyricsAnnotationMode.furigana && line.furigana.isNotEmpty) {
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
          ),
        ));
        absoluteCursor += seg.text.characters.length;
      }
      return Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 0, runSpacing: 3, children: widgets);
    }
    if (current && settings.verbatim && line.words.isNotEmpty) {
      return _KaraokeLineText(line: line, playbackMs: playbackMs, fontSize: 23);
    }
    return Text(
      line.text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: current ? 1 : .40),
        fontSize: current ? 23 : 16,
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
  const _KaraokeLineText({required this.line, required this.playbackMs, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    for (final word in line.words) {
      final chars = word.text.characters.toList();
      final total = math.max(1, word.endMs - word.startMs);
      for (var i = 0; i < chars.length; i++) {
        final start = word.startMs + (total * i / chars.length).round();
        final end = word.startMs + (total * (i + 1) / chars.length).round();
        final progress = ((playbackMs - start) / math.max(1, end - start)).clamp(0.0, 1.0);
        final color = Color.lerp(
          Colors.white.withValues(alpha: .25),
          Colors.white,
          progress,
        );
        spans.add(TextSpan(
          text: chars[i],
          style: TextStyle(
            color: color,
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

  const _FuriganaSegmentView({required this.segment, required this.current, required this.playbackMs, required this.absoluteStart, required this.wordRanges});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: Colors.white.withValues(alpha: current ? 1 : .4), fontSize: current ? 23 : 16, height: 1.2, fontWeight: current ? FontWeight.w800 : FontWeight.w500);
    final spans = <TextSpan>[];
    final chars = segment.text.characters.toList();
    for (var i = 0; i < chars.length; i++) {
      final absolute = absoluteStart + i;
      var color = base.color;
      if (current && context.read<SettingsStore>().verbatim && wordRanges.isNotEmpty) {
        for (final range in wordRanges) {
          if (absolute >= range.start && absolute < range.end) {
            final total = math.max(1, range.word.endMs - range.word.startMs);
            final progress = ((playbackMs - range.word.startMs) / total).clamp(0.0, 1.0);
            color = Color.lerp(Colors.white.withValues(alpha: .25), Colors.white, progress);
            break;
          }
        }
      }
      spans.add(TextSpan(text: chars[i], style: base.copyWith(color: color)));
    }
    final body = Text.rich(TextSpan(children: spans));
    if (segment.reading == null || segment.reading!.isEmpty) return body;
    return Column(mainAxisSize: MainAxisSize.min, children: [Text(segment.reading!, style: TextStyle(color: Colors.white.withValues(alpha: current ? .65 : .28), fontSize: current ? 9 : 7)), body]);
  }
}

class _PlaybackControls extends StatelessWidget {
  final Track track;
  final PlayerController player;
  final VoidCallback onQueue;
  final bool showVolume;

  const _PlaybackControls({
    required this.track,
    required this.player,
    required this.onQueue,
    this.showVolume = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = player.duration.inMilliseconds > 0
        ? player.duration.inMilliseconds
        : track.durationMs;
    final value = player.position.inMilliseconds
        .clamp(0, math.max(1, maxMs))
        .toDouble();
    final liked = context.watch<AccountStore>().liked(track.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;

        // Keep the three bottom actions anchored in one stable row.
        // The space above them is deliberately distributed between the
        // transport controls and the volume slider.
        final controlHeight = narrow ? 240.0 : 256.0;
        final transportIcon = narrow ? 31.0 : 34.0;
        final transportHit = narrow ? 52.0 : 58.0;
        final playIcon = narrow ? 37.0 : 41.0;
        final playHit = narrow ? 68.0 : 74.0;
        final secondaryIcon = narrow ? 21.0 : 23.0;
        final secondaryHit = narrow ? 52.0 : 56.0;
        final transportGap = narrow ? 22.0 : 30.0;

        return SizedBox(
          height: controlHeight,
          child: Column(
            children: [
              // Keep the timeline at the already-correct upward position.
              Transform.translate(
                offset: const Offset(0, -8),
                child: Row(
                  children: [
                    Text(
                      formatDuration(player.position),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: math.max(1, maxMs).toDouble(),
                          onChanged: (v) => player.seek(
                            Duration(milliseconds: v.round()),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      formatDuration(
                        player.duration.inMilliseconds > 0
                            ? player.duration
                            : track.duration,
                      ),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // This is the main visual breathing space immediately below
              // the timeline.
              const SizedBox(height: 14),

              // Plain, solid Cupertino-style transport glyphs, matching the
              // reference screenshot more closely than a white play button
              // inside a separate circle.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlIcon(
                    icon: CupertinoIcons.backward_end_fill,
                    size: transportIcon,
                    buttonSize: transportHit,
                    onTap: player.previous,
                    label: '上一首',
                  ),
                  SizedBox(width: transportGap),
                  _ControlIcon(
                    icon: player.isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: playIcon,
                    buttonSize: playHit,
                    onTap: player.toggle,
                    label: player.isPlaying ? '暂停' : '播放',
                  ),
                  SizedBox(width: transportGap),
                  _ControlIcon(
                    icon: CupertinoIcons.forward_end_fill,
                    size: transportIcon,
                    buttonSize: transportHit,
                    onTap: player.next,
                    label: '下一首',
                  ),
                ],
              ),

              if (showVolume) ...[
                const SizedBox(height: 10),
                _VolumeControlBar(
                  player: player,
                  width: math.min(320, constraints.maxWidth),
                ),
              ],

              // Absorb the remaining vertical space here. This keeps the
              // bottom three controls fixed without forcing the progress bar,
              // transport row, and volume row to bunch together.
              const Spacer(),

              // Stable bottom row: heart / playback mode / queue.
              SizedBox(
                width: math.min(330, constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlIcon(
                      icon: liked
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      size: secondaryIcon,
                      buttonSize: secondaryHit,
                      active: liked,
                      circleBackground: true,
                      onTap: () async {
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
                      label: liked ? '取消喜欢' : '喜欢',
                    ),
                    _ControlIcon(
                      icon: player.playbackModeIcon,
                      size: secondaryIcon,
                      buttonSize: secondaryHit,
                      active: player.playbackModeLabel != '顺序播放',
                      circleBackground: true,
                      onTap: player.cyclePlaybackMode,
                      label: player.playbackModeLabel,
                    ),
                    _ControlIcon(
                      icon: CupertinoIcons.list_bullet,
                      size: secondaryIcon,
                      buttonSize: secondaryHit,
                      circleBackground: true,
                      onTap: onQueue,
                      label: '播放队列',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black87;
    final active = isDark ? Colors.white : Colors.black87;
    final inactive = isDark ? Colors.white30 : Colors.black26;
    final shadow = isDark ? Colors.black54 : Colors.white70;

    return Container(
      width: width,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(
            value <= 0.01
                ? CupertinoIcons.speaker_slash_fill
                : value < 0.5
                    ? CupertinoIcons.speaker_1_fill
                    : CupertinoIcons.speaker_3_fill,
            color: foreground,
            size: 17,
            shadows: [Shadow(color: shadow, blurRadius: 3)],
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: active,
                inactiveTrackColor: inactive,
                thumbColor: active,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5,
                ),
                overlayColor: active.withValues(alpha: .10),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12,
                ),
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
          Icon(
            CupertinoIcons.speaker_3_fill,
            color: foreground,
            size: 17,
            shadows: [Shadow(color: shadow, blurRadius: 3)],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black87;
    final iconColor = active ? const Color(0xFFFF5A66) : foreground;
    final background = circleBackground
        ? (isDark ? Colors.black : Colors.white).withValues(alpha: .16)
        : Colors.transparent;
    final shadowColor = isDark ? Colors.black.withValues(alpha: .55) : Colors.white.withValues(alpha: .75);

    final child = Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        splashColor: iconColor.withValues(alpha: .10),
        highlightColor: iconColor.withValues(alpha: .06),
        onTap: onTap,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Center(
            child: Icon(
              icon,
              color: iconColor,
              size: size,
              shadows: [Shadow(color: shadowColor, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );

    return label == null
        ? child
        : Tooltip(message: label!, child: child);
  }
}

