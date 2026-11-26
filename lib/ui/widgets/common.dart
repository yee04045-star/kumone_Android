import 'dart:io';
import 'route_snapshot.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/models/models.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/wallpaper_store.dart';
import 'liquid_surface.dart';
import '../theme/player_surface_theme.dart';
import 'marquee_text.dart';
import 'top_blur_distribution.dart';
import 'wallpaper_scope.dart';
import '../../core/api/netease_api.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';

Widget? _iosBackButton(BuildContext context, bool automaticallyImplyLeading) {
  if (!automaticallyImplyLeading ||
      ModalRoute.of(context)?.impliesAppBarDismissal != true) {
    return null;
  }
  final settings = context.watch<SettingsStore?>();
  return Padding(padding: const EdgeInsets.only(left: 10),
    child: Center(child: SizedBox(width: 42, height: 42,
    child: KumoneLiquidSurface(radius: 999, interactive: false,
      backingOpacity: settings?.menuBackingOpacity ?? .5,
      blur: settings?.songMenuBlur ?? 3,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        // Balance the chevron's asymmetric ink, not just its font box.
        icon: Transform.translate(offset: const Offset(-1, 0),
          child: Icon(CupertinoIcons.chevron_back, size: 24,
            shadows: [for (final offset in const [Offset(-.35, 0), Offset(.35, 0),
              Offset(0, -.35), Offset(0, .35)]) Shadow(
                color: Theme.of(context).colorScheme.onSurface, offset: offset)])),
        onPressed: () => Navigator.of(context).maybePop())))));
}

SystemUiOverlayStyle kumoneGlassStatusBarStyle(BuildContext context) {
  final theme = Theme.of(context);
  final wallpaper = context.watch<WallpaperStore?>();
  final settings = context.watch<SettingsStore?>();
  var darkIcons = theme.brightness == Brightness.light;
  Color? stripColor;
  final landscape = MediaQuery.sizeOf(context).aspectRatio > 1;
  final enabled = wallpaper?.pathFor(landscape) != null;
  final sampled = wallpaper?.statusColorFor(landscape);
  if (enabled && sampled != null) {
    final background = Color.alphaBlend(
      (wallpaper!.darkFor(landscape) ? Colors.black : Colors.white).withValues(alpha: .24),
      sampled,
    );
    stripColor = background;
    final frosted = Color.alphaBlend(
      theme.colorScheme.surface.withValues(alpha: .10), background);
    darkIcons = frosted.computeLuminance() > .42;
  }
  return SystemUiOverlayStyle(
    statusBarColor: settings?.backgroundExtend == false &&
        enabled
            ? (stripColor ?? theme.scaffoldBackgroundColor) : Colors.transparent,
    statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
    statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );
}

double kumoneToolbarInset(BuildContext context) =>
    kToolbarHeight + MediaQuery.paddingOf(context).top;

class KumoneGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final bool? centerTitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;
  final double? titleSpacing;
  final bool primary;

  const KumoneGlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.centerTitle,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
    this.titleSpacing,
    this.primary = true,
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title is Text && (title as Text).data != null
          ? MarqueeText((title as Text).data!, style: (title as Text).style)
          : title,
      actions: actions,
      centerTitle: centerTitle,
      leading: leading ?? _iosBackButton(context, automaticallyImplyLeading),
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: toolbarHeight,
      systemOverlayStyle: kumoneGlassStatusBarStyle(context),
      titleSpacing: titleSpacing,
      primary: primary,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: const _KumoneGlassBarSurface(),
    );
  }
}

class KumoneGlassSliverAppBar extends StatelessWidget {
  final Widget? title;
  final List<Widget>? actions;
  final bool? centerTitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool pinned;
  final PreferredSizeWidget? bottom;
  final double? toolbarHeight;
  final double? titleSpacing;
  final bool primary;

  const KumoneGlassSliverAppBar({
    super.key,
    this.title,
    this.actions,
    this.centerTitle,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.pinned = true,
    this.bottom,
    this.toolbarHeight,
    this.titleSpacing,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: pinned,
      title: title is Text && (title as Text).data != null
          ? MarqueeText((title as Text).data!, style: (title as Text).style)
          : title,
      actions: actions,
      centerTitle: centerTitle,
      leading: leading ?? _iosBackButton(context, automaticallyImplyLeading),
      automaticallyImplyLeading: automaticallyImplyLeading,
      bottom: bottom,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      systemOverlayStyle: kumoneGlassStatusBarStyle(context),
      titleSpacing: titleSpacing,
      primary: primary,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: const _KumoneGlassBarSurface(),
    );
  }
}

class _KumoneGlassBarSurface extends StatelessWidget {
  final bool followScroll;
  final double? scrollProgress;
  final double? baseHeight;
  const _KumoneGlassBarSurface({this.followScroll = true,
    this.scrollProgress, this.baseHeight});

  @override
  Widget build(BuildContext context) {
    final progress = scrollProgress ?? (followScroll
        ? (_TopBlurProgress.maybeOf(context)?.value ?? 0.0) : 1.0);
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsStore?>();
    final distribution = settings?.topBlurDistribution ?? 1;
    final extent = settings?.topBlurExtent ?? 1;
    return IgnorePointer(child: LayoutBuilder(builder: (context, constraints) {
      // Extend paint only; never enlarge toolbar layout or steal list gestures.
      return OverflowBox(alignment: Alignment.topCenter,
        minHeight: (baseHeight ?? constraints.maxHeight) * extent,
        maxHeight: (baseHeight ?? constraints.maxHeight) * extent,
        child: LiquidGlassScrollEdge(
          edge: LiquidGlassEdge.top,
          blur: 26 * progress,
          color: scheme.surface.withValues(alpha: .10 * progress),
          curve: Curves.easeInOut,
          blurCurve: KumoneTopBlurDistribution(distribution),
        ),
      );
    }));
  }
}

// Use the platform's coordinated incoming/outgoing transition and edge-swipe
// back gesture. The player is presented vertically without changing its layout.
Route<T> kumonePageRoute<T>(Widget page, {RouteSettings? settings}) =>
    settings?.name == '/now-playing'
        ? _KumonePlayerRoute<T>(page: page, settings: settings)
        : _KumonePageRoute<T>(page: page, settings: settings);

class _KumonePageRoute<T> extends CupertinoPageRoute<T> {
  _KumonePageRoute({required Widget page, super.settings})
      : super(builder: (_) => settings?.name == '/now-playing'
              ? page : KumoneWallpaperRouteSurface(
                  settingsPage: settings?.name == '/settings',
                  child: KumoneTopBlurScrollScope(child: page)),
          fullscreenDialog: settings?.name == '/now-playing');

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return super.buildTransitions(context, animation, secondaryAnimation,
        KumoneRouteSnapshot(covered: secondaryAnimation, child: child));
  }
}

// Transparent route keeps the outgoing page/snapshot painted under drag exit.
// The live player is deliberately never wrapped in SnapshotWidget.
class _KumonePlayerRoute<T> extends PageRouteBuilder<T> {
  _KumonePlayerRoute({required Widget page, super.settings}) : super(
    opaque: false, fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic)), child: child));
}

Future<T?> kumoneDialog<T>({required BuildContext context,
    required WidgetBuilder builder}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = RawDialogRoute<T>(
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: .28),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => SafeArea(child: builder(context)),
    transitionBuilder: (context, animation, _, child) {
      final curved = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
      return FadeTransition(opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: .96, end: 1)
            .animate(curved), child: child));
    },
  );
  final result = await navigator.push(route);
  // A popped route remains mounted during its reverse animation. Delay callers
  // disposing text controllers until its overlay has actually been removed.
  await route.completed;
  return result;
}

class KumoneInteractive extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool enabled;

  const KumoneInteractive({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.enabled = true,
  });

  @override
  State<KumoneInteractive> createState() => _KumoneInteractiveState();
}

class _KumoneInteractiveState extends State<KumoneInteractive> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!_pressed && !value || _pressed && value) return;
    if (mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? .985 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onHighlightChanged: widget.enabled ? _setPressed : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: widget.child,
        ),
      ),
    );
  }
}

class HomeAppear extends StatefulWidget {
  final Widget child;
  final int index;
  final bool enabled;
  const HomeAppear({super.key, required this.child, this.index = 0,
    this.enabled = true});

  @override
  State<HomeAppear> createState() => _HomeAppearState();
}

class _HomeAppearState extends State<HomeAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, .045),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    final delay = Duration(milliseconds: (widget.index.clamp(0, 8)) * 40);
    Future<void>.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class Artwork extends StatefulWidget {
  final String? url;
  final Future<String?> Function()? resolveUrl;
  final double size;
  final double radius;
  final bool circle;
  final bool shadow;
  final bool border;
  final bool fadeIn;
  final double scale;

  const Artwork({
    super.key,
    this.url,
    this.resolveUrl,
    required this.size,
    this.radius = 12,
    this.circle = false,
    this.shadow = true,
    this.border = false,
    this.fadeIn = false,
    this.scale = 1.0,
  });

  @override
  State<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<Artwork> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _candidate = 0;
  bool _advancing = false;
  bool _resolving = false;
  bool _resolverAttempted = false;
  String? _resolvedUrl;
  String? _lastUrl;

  List<String> _candidates() {
    final raw = (_resolvedUrl ?? widget.url)?.trim();
    if (raw == null || raw.isEmpty) return const [];
    var base = raw;
    if (base.startsWith('//')) base = 'https:$base';
    if (base.startsWith('http://')) base = 'https://${base.substring(7)}';
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) return <String>[base];

    final hosts = <String>[uri.host];
    // NetEase artwork commonly comes from p1..p4.music.126.net.  Keep the
    // original host first (matching iOS), then rotate through the same CDN
    // pool when one edge is unavailable on a particular Android network.
    if (RegExp(r'^p[1-4]\.music\.126\.net$').hasMatch(uri.host)) {
      for (final host in const [
        'p1.music.126.net',
        'p2.music.126.net',
        'p3.music.126.net',
        'p4.music.126.net'
      ]) {
        if (!hosts.contains(host)) hosts.add(host);
      }
    }

    final values = <String>[];
    final thumb = widget.size <= 64;
    final requestSize = thumb ? 192 : 768;
    for (final host in hosts) {
      final image = uri.replace(host: host);
      final isNetease = host.endsWith('.music.126.net');
      values.add(isNetease ? image.replace(queryParameters: {
        ...image.queryParameters, 'param': '${requestSize}y$requestSize',
      }).toString() : image.toString());
    }
    return values.toSet().toList(growable: false);
  }

  void _advance() {
    if (!mounted || _advancing) return;
    final urls = _candidates();
    if (_candidate + 1 >= urls.length) {
      _resolveFreshUrl();
      return;
    }
    _advancing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _candidate += 1;
        _advancing = false;
      });
    });
  }

  void _resolveFreshUrl() {
    if (!mounted ||
        _resolving ||
        _resolverAttempted ||
        widget.resolveUrl == null) {
      return;
    }
    _resolverAttempted = true;
    _resolving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final fresh = await widget.resolveUrl!();
        if (!mounted) return;
        final trimmed = fresh?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          setState(() {
            _resolvedUrl = trimmed;
            _candidate = 0;
          });
        }
      } catch (_) {
        // Recovery only; keep the placeholder when the API is unavailable.
      } finally {
        if (mounted) _resolving = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant Artwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _candidate = 0;
      _advancing = false;
      _resolving = false;
      _resolverAttempted = false;
      _resolvedUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final urls = _candidates();
    if (_lastUrl != widget.url) {
      _lastUrl = widget.url;
      _candidate =
          _candidate.clamp(0, urls.isEmpty ? 0 : urls.length - 1).toInt();
    }
    if (urls.isEmpty && widget.resolveUrl != null && !_resolverAttempted) {
      _resolveFreshUrl();
    }
    final shape = widget.circle ? BoxShape.circle : BoxShape.rectangle;
    final borderRadius = widget.circle
        ? BorderRadius.zero
        : BorderRadius.circular(widget.radius);
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded,
          size: widget.size * .28, color: cs.onSurfaceVariant),
    );

    Widget child = fallback;
    if (urls.isNotEmpty && Uri.tryParse(urls[_candidate])?.scheme == 'file') {
      child = Image.file(File.fromUri(Uri.parse(urls[_candidate])), fit: BoxFit.cover,
        cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(64, 768),
        errorBuilder: (_, __, ___) => fallback);
    } else if (urls.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: urls[_candidate],
        memCacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(64, 768),
        useOldImageOnUrlChange: true,
        httpHeaders: const {
          'Referer': 'https://music.163.com/',
          'User-Agent':
              'Mozilla/5.0 (Android) AppleWebKit/537.36 Chrome/125.0 Mobile Safari/537.36',
        },
        fit: BoxFit.cover,
        fadeInDuration: widget.fadeIn ? const Duration(milliseconds: 320) : Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) {
          _advance();
          return fallback;
        },
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: widget.circle ? null : borderRadius,
        color: Colors.transparent,
        border: widget.border
            ? Border.all(color: cs.onSurface.withValues(alpha: .07), width: .5)
            : null,
        boxShadow: widget.shadow
            ? [
                BoxShadow(
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                    color: Colors.black.withValues(alpha: .10))
              ]
            : const [],
      ),
      child: Transform.scale(
        scale: widget.scale * 1.006,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final double horizontalPadding;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.horizontalPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -.25,
        );
    if (showChevron && onTap != null && trailing == null) {
      return Padding(padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 14),
        child: Align(alignment: Alignment.centerLeft,
          child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: titleStyle), const SizedBox(width: 5),
                Transform.translate(offset: const Offset(0, 1.5),
                  child: Icon(Icons.chevron_right_rounded, size: 23, color: cs.onSurfaceVariant)),
              ])))));
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 14),
      child: Row(
        children: [
          Text(title, style: titleStyle),
          const Spacer(),
          if (trailing != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(1, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(trailing!),
            ),
          if (showChevron)
            Icon(Icons.chevron_right_rounded,
                size: 20, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class PlaylistCard extends StatelessWidget {
  final PlaylistSummary item;
  final VoidCallback onTap;
  final double width;
  final VoidCallback? onPlay;
  final Future<String?> Function()? resolveArtwork;

  const PlaylistCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 160,
    this.onPlay,
    this.resolveArtwork,
  });

  @override
  Widget build(BuildContext context) {
    return KumoneInteractive(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Hero(
                  tag: 'playlist-cover-${item.id}',
                  child: Artwork(
                    url: item.coverUrl,
                    resolveUrl: resolveArtwork ??
                        () => NeteaseApi.instance.playlistCover(item.id),
                    size: width,
                    radius: 9,
                    shadow: false,
                  ),
                ),
                if (item.playCount > 0)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: _CountBadge(count: item.playCount),
                  ),
                if (onPlay != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: .52),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onPlay,
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 19),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            if (item.copywriter != null && item.copywriter!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  item.copywriter!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              formatCount(count),
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackRow extends StatelessWidget {
  final Track track;
  final PlayerController player;
  final AccountStore account;
  final int? index;

  const TrackRow({
    super.key,
    required this.track,
    required this.player,
    required this.account,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final active = player.currentTrack?.id == track.id;
    final cs = Theme.of(context).colorScheme;
    return TrackActionMenu(
      track: track,
      showButton: false,
      child: Dismissible(
        key: ValueKey('${track.id}-${index ?? 0}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          color: cs.error,
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (_) async {
          player.removeFromQueue(track);
          return true;
        },
        child: Material(
          color:
              active ? cs.primary.withValues(alpha: .065) : Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Artwork(
                      url: track.album.picUrl,
                      size: 46,
                      radius: 8,
                      shadow: false),
                  if (active)
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .44),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        player.isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.pause_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
            title: Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? cs.primary : null,
              ),
            ),
            subtitle: Text(
              track.artistNames.isEmpty
                  ? (track.album.name.isEmpty ? '未知艺术家' : track.album.name)
                  : track.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => player.playTrack(track),
          ),
        ),
      ),
    );
  }
}

class GlassMiniPlayer extends StatelessWidget {
  final PlayerController player;
  final VoidCallback onOpen;
  final VoidCallback onQueue;

  const GlassMiniPlayer({
    super.key,
    required this.player,
    required this.onOpen,
    required this.onQueue,
  });

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return TooltipVisibility(visible: false,
      child: RawGestureDetector(
        gestures: {LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 500)),
          (recognizer) => recognizer.onLongPress = onQueue)},
        child: Material(
      color: Colors.transparent,
      child: KumoneLiquidSurface(
        radius: 999,
        backingOpacity: context.watch<SettingsStore>().chromeBackingOpacity,
        blur: context.watch<SettingsStore>().chromeBlur,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onOpen,
              child: Artwork(
                  url: track.album.picUrl, size: 34, radius: 7, shadow: false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MarqueeText(
                        track.name,
                        style: const TextStyle(fontSize: 13, height: 1.15, fontWeight: FontWeight.w700),
                      ),
                      MarqueeText(
                        track.artistNames,
                        style:
                            TextStyle(fontSize: 10, height: 1.15, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(tooltip: '上一首', onPressed: player.previous,
              icon: const Icon(CupertinoIcons.backward_fill)),
            IconButton(
              tooltip: player.isPlaying ? '暂停' : '播放', onPressed: player.toggle,
              icon: Transform.translate(
                offset: Offset(player.isPlaying ? 0 : 2, 0),
                child: Icon(player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill))),
            IconButton(tooltip: '下一首', onPressed: player.next,
              icon: const Icon(CupertinoIcons.forward_fill)),
          ],
        ),
      ),
    )));
  }
}

class _SongFocusPainter extends CustomPainter {
  final Rect row;
  const _SongFocusPainter(this.row);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(row, const Radius.circular(12)));
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .24));
  }
  @override
  bool shouldRepaint(_SongFocusPainter oldDelegate) => row != oldDelegate.row;
}

class TrackActionMenu extends StatefulWidget {
  final Track track;
  final bool allowRemoveFromPlaylist;
  final Future<void> Function()? onRemoveFromPlaylist;
  final Future<void> Function()? onDeleteFromCloud;
  final Future<void> Function(Track replacement)? onRecommendationReduced;
  final ValueChanged<AlbumRef>? onOpenAlbum;
  final ValueChanged<ArtistRef>? onOpenArtist;
  final bool glassMenu;
  final bool plainPlayerButton;
  final double playerButtonSize;
  final double playerIconSize;
  final Color? glassMenuPrimary;
  final Color? glassMenuSecondary;
  final bool showButton;
  final Widget? child;

  const TrackActionMenu({
    super.key,
    required this.track,
    this.allowRemoveFromPlaylist = false,
    this.onRemoveFromPlaylist,
    this.onDeleteFromCloud,
    this.onRecommendationReduced,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.glassMenu = false,
    this.plainPlayerButton = false,
    this.playerButtonSize = 42,
    this.playerIconSize = 23,
    this.glassMenuPrimary,
    this.glassMenuSecondary,
    this.showButton = true,
    this.child,
  });

  @override
  State<TrackActionMenu> createState() => _TrackActionMenuState();
}

class _TrackActionMenuState extends State<TrackActionMenu> {
  // Only one track context menu is allowed to be visible at a time.  Each
  // list row owns its own TrackActionMenu state, so keeping the active state
  // here gives us the same single-context-menu behavior as a native list.
  static _TrackActionMenuState? _activeMenuState;

  bool _rowPressed = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;
  LocalHistoryEntry? _history;

  bool get _isOpen => _entry != null;

  @override
  void dispose() {
    _removeOverlay();
    if (identical(_activeMenuState, this)) {
      _activeMenuState = null;
    }
    super.dispose();
  }

  void _removeOverlay() {
    final entry = _entry;
    _entry = null;
    if (identical(_activeMenuState, this)) {
      _activeMenuState = null;
    }
    entry?.remove();
    final history = _history;
    _history = null;
    history?.remove();
  }

  void _insertOverlay(OverlayState overlay) {
    _activeMenuState = this;
    _history = LocalHistoryEntry(onRemove: () {
      _history = null;
      _removeOverlay();
    });
    ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    overlay.insert(_entry!);
  }

  void _closeAnyActiveMenu() {
    final active = _activeMenuState;
    if (active != null && !identical(active, this)) {
      active._removeOverlay();
    }
  }

  int get _glassMenuItemCount {
    var count = 3; // next, like, add
    if (widget.onOpenAlbum != null) count += 1;
    count += widget.track.artists.take(3).length;
    if (widget.allowRemoveFromPlaylist) count += 1;
    if (widget.onDeleteFromCloud != null) count += 1;
    if (widget.onRecommendationReduced != null) count += 1;
    return count;
  }

  String _artistMenuLabel(String name, double panelWidth) {
    final label = '查看歌手：$name';
    final painter = TextPainter(text: TextSpan(text: label,
      style: const TextStyle(fontSize: 15.5, height: 1.2, fontWeight: FontWeight.w500)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context), maxLines: 1)
      ..layout();
    final needsWrap = painter.width > math.max(1, panelWidth - 46);
    painter.dispose();
    return needsWrap ? '查看歌手：${String.fromCharCode(10)}$name' : label;
  }

  double _menuRowHeight(String label, double panelWidth) {
    final painter = TextPainter(text: TextSpan(text: label,
      style: const TextStyle(fontSize: 15.5, height: 1.2, fontWeight: FontWeight.w500)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: math.max(1, panelWidth - 46));
    final height = math.max(48.0, painter.height + 20);
    painter.dispose();
    return height;
  }

  double _glassMenuNaturalHeight(double panelWidth) {
    var height = _glassMenuItemCount * 48.0 + 16;
    if (widget.onOpenArtist != null) {
      for (final artist in widget.track.artists.take(3)) {
        height += _menuRowHeight(_artistMenuLabel(artist.name, panelWidth), panelWidth) - 48;
      }
    }
    return math.min(500, height);
  }

  void _toggleGlassMenu() {
    if (_isOpen) {
      _removeOverlay();
      return;
    }

    _closeAnyActiveMenu();

    final sourceBox = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (sourceBox == null || overlayBox == null) return;

    final sourceTopLeft = sourceBox.localToGlobal(Offset.zero);
    final sourceBottomRight =
        sourceTopLeft + sourceBox.size.bottomRight(Offset.zero);
    final bottomRight = overlayBox.globalToLocal(sourceBottomRight);
    final overlaySize = overlayBox.size;
    final insets = MediaQuery.paddingOf(context);
    final panelWidth = math.min(220.0, overlaySize.width - 24);
    final estimatedHeight = math.min(
        _glassMenuNaturalHeight(panelWidth), overlaySize.height - insets.vertical - 32);
    final right = (overlaySize.width - bottomRight.dx)
        .clamp(12.0, math.max(12.0, overlaySize.width - panelWidth - 12))
        .toDouble();
    final maxTop = math.max(insets.top + 12,
        overlaySize.height - insets.bottom - estimatedHeight - 12);
    final top = (bottomRight.dy + 8).clamp(insets.top + 12, maxTop).toDouble();

    _entry = OverlayEntry(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            right: right,
            top: top,
            child:
                SizedBox(width: panelWidth, child: _glassMenuPanel(panelWidth)),
          ),
        ],
      ),
    );
    _insertOverlay(overlay);
  }

  Widget _glassMenuPanel(double panelWidth) {
    final theme = kumonePlayerSurfaceTheme(Theme.of(context),
        widget.glassMenuPrimary, widget.glassMenuSecondary);
    final dark = theme.brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    final actions = <Widget>[];

    void add(IconData icon, String label, String value) {
      actions.add(InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => _selectGlass(value),
        child: SizedBox(height: _menuRowHeight(label, panelWidth),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Align(alignment: Alignment.centerLeft,
              child: Text(label, softWrap: true, maxLines: null, overflow: TextOverflow.visible,
                style: TextStyle(fontSize: 15.5, height: 1.2,
                  fontWeight: FontWeight.w500, color: foreground)))))));
    }

    add(CupertinoIcons.arrow_down, '下一首播放', 'next');
    add(
      CupertinoIcons.heart,
      context.read<AccountStore>().liked(widget.track.id) ? '取消喜欢' : '喜欢',
      'like',
    );
    add(CupertinoIcons.music_note_list, '添加到歌单', 'add');
    if (widget.onOpenAlbum != null) {
      add(CupertinoIcons.music_albums, '查看专辑', 'album');
    }
    if (widget.onOpenArtist != null) {
      for (final artist in widget.track.artists.take(3)) {
        add(CupertinoIcons.person, _artistMenuLabel(artist.name, panelWidth),
            'artist:${artist.id}');
      }
    }
    if (widget.allowRemoveFromPlaylist) {
      add(CupertinoIcons.minus_circle, '从此歌单移除', 'remove');
    }
    if (widget.onDeleteFromCloud != null) {
      add(CupertinoIcons.cloud, '从音乐云盘删除', 'cloud_delete');
    }
    if (widget.onRecommendationReduced != null) {
      add(CupertinoIcons.minus_circle, '减少推荐', 'reduce');
    }

    return Theme(data: theme, child: Consumer<SettingsStore>(
      builder: (context, settings, _) => TweenAnimationBuilder<double>(
        tween: Tween(begin: .985, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        builder: (_, scale, child) => Transform.scale(
          scale: scale,
          alignment: Alignment.topRight,
          child: child,
        ),
        child: KumoneLiquidSurface(
          radius: 22,
          backingOpacity: settings.menuBackingOpacity,
          blur: settings.songMenuBlur,
          padding: const EdgeInsets.fromLTRB(7, 8, 7, 8),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(
                    500,
                    MediaQuery.sizeOf(context).height -
                        MediaQuery.paddingOf(context).vertical -
                        32),
              ),
              child: SingleChildScrollView(
                child: Theme(
                  data: theme.copyWith(
                      iconTheme: IconThemeData(color: foreground)),
                  child:
                      Column(mainAxisSize: MainAxisSize.min, children: actions),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _selectGlass(String value) async {
    _removeOverlay();
    final player = context.read<PlayerController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (value.startsWith('blacklist:')) {
      final artist = value.startsWith('blacklist:artist:');
      final id = artist ? int.tryParse(value.split(':').last) : widget.track.id;
      if (id == null) return;
      final confirmed = await kumoneDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(artist ? '屏蔽这位歌手？' : '屏蔽这首歌？'),
          content: const Text('将加入当前账号的音乐黑名单，影响服务端后续推荐。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('屏蔽')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await NeteaseApi.instance.addToMusicBlacklist(id, artist: artist);
        if (mounted) {
          messenger?.showSnackBar(const SnackBar(content: Text('已加入音乐黑名单')));
        }
      } catch (e) {
        if (mounted) messenger?.showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (value == 'next') {
      try {
        player.insertAsNext(widget.track);
        player.showNotice('已加入下一首播放');
      } catch (_) {
        player.showNotice('加入失败');
      }
      return;
    }
    if (value == 'like') {
      await _like(context);
      return;
    }
    if (value == 'add') {
      await showAddToPlaylistSheet(context, widget.track);
      return;
    }
    if (value == 'album') {
      widget.onOpenAlbum?.call(widget.track.album);
      return;
    }
    if (value.startsWith('artist:')) {
      final id = int.tryParse(value.substring(7));
      ArtistRef? artist;
      if (id != null) {
        for (final candidate in widget.track.artists) {
          if (candidate.id == id) {
            artist = candidate;
            break;
          }
        }
      }
      if (artist != null) widget.onOpenArtist?.call(artist);
      return;
    }
    if (value == 'remove') {
      await _remove(context);
      return;
    }
    if (value == 'cloud_delete') {
      await _deleteCloud(context);
      return;
    }
    if (value == 'reduce') {
      await _reduceRecommendation(context);
      return;
    }
    if (value == 'copy') {
      await Clipboard.setData(
        ClipboardData(
            text: 'https://music.163.com/#/song?id=${widget.track.id}'),
      );
      if (messenger == null || !messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('歌曲链接已复制')),
      );
    }
  }

  Future<void> _like(BuildContext context) async {
    final account = context.read<AccountStore>();
    final player = context.read<PlayerController>();
    final wasLiked = account.liked(widget.track.id);
    try {
      await account.toggleLike(widget.track.id);
      player.showNotice(wasLiked ? '已取消喜欢' : '已加入喜欢');
    } catch (e) {
      player.showNotice('$e');
    }
  }

  Future<void> _remove(BuildContext context) async {
    final player = context.read<PlayerController>();
    try {
      final callback = widget.onRemoveFromPlaylist;
      if (callback != null) await callback();
      if (context.mounted) {
        player.showNotice('已从歌单移除');
      }
    } catch (e) {
      if (context.mounted) {
        player.showNotice('$e');
      }
    }
  }

  Future<void> _deleteCloud(BuildContext context) async {
    try {
      final callback = widget.onDeleteFromCloud;
      if (callback != null) await callback();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已从音乐云盘删除')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _reduceRecommendation(BuildContext context) async {
    try {
      final replacement =
          await NeteaseApi.instance.dislikeRecommendedSong(widget.track.id);
      final callback = widget.onRecommendationReduced;
      if (callback != null) await callback(replacement);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已减少推荐')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _showStandardMenuAt(Offset globalPosition) {
    if (_isOpen) {
      _removeOverlay();
      return;
    }

    _closeAnyActiveMenu();

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final sourceBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final size = overlayBox.size;
    final point = overlayBox.globalToLocal(globalPosition);

    final panelWidth = math.min(220.0, size.width - 24);
    const edgeInset = 12.0;
    const gap = 8.0;
    final insets = MediaQuery.paddingOf(context);
    final minTop = insets.top + edgeInset;
    final maxBottom = size.height - insets.bottom - edgeInset;
    final panelHeight =
        math.min(_glassMenuNaturalHeight(panelWidth), math.max(48.0, maxBottom - minTop));

    final maxLeft = math.max(edgeInset, size.width - panelWidth - edgeInset);
    final left =
        (point.dx - panelWidth * .50).clamp(edgeInset, maxLeft).toDouble();

    // Anchor to the pressed row rather than to a fixed 430px rectangle.  The
    // real menu is often only ~300px tall, and using the old fixed height
    // created a large artificial gap when the menu was flipped above the row.
    final sourceTopLeft = sourceBox?.localToGlobal(Offset.zero);
    final sourceBottomRight = sourceBox == null
        ? null
        : sourceTopLeft! + sourceBox.size.bottomRight(Offset.zero);
    final anchorTop = sourceBottomRight == null
        ? point.dy
        : overlayBox.globalToLocal(sourceTopLeft!).dy;
    final anchorBottom = sourceBottomRight == null
        ? point.dy
        : overlayBox.globalToLocal(sourceBottomRight).dy;

    final downTop = anchorBottom + gap;
    final upTop = anchorTop - panelHeight - gap;
    final canPlaceDown = downTop + panelHeight <= maxBottom;
    final canPlaceUp = upTop >= minTop;
    final top = canPlaceDown
        ? downTop
        : (canPlaceUp
            ? upTop
            : upTop
                .clamp(minTop, math.max(minTop, maxBottom - panelHeight))
                .toDouble());

    final focus = context.read<SettingsStore>().songMenuFocus;
    final rowRect = sourceBox == null ? Rect.zero :
        overlayBox.globalToLocal(sourceBox.localToGlobal(Offset.zero)) & sourceBox.size;
    _entry = OverlayEntry(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
              child: focus ? CustomPaint(painter: _SongFocusPainter(rowRect))
                  : const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: SizedBox(
              width: panelWidth,
              child: _glassMenuPanel(panelWidth),
            ),
          ),
        ],
      ),
    );
    _insertOverlay(overlay);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.glassMenu) {
      return CompositedTransformTarget(
        link: _layerLink,
        child: Material(
          color: widget.plainPlayerButton ? Colors.transparent : Colors.black.withValues(alpha: .18),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withValues(alpha: .10),
            highlightColor: Colors.white.withValues(alpha: .06),
            onTap: _toggleGlassMenu,
            child: SizedBox(
              width: widget.playerButtonSize,
              height: widget.playerButtonSize,
              child: Icon(Icons.more_horiz_rounded, color: Colors.white,
                  size: widget.playerIconSize),
            ),
          ),
        ),
      );
    }

    if (!widget.showButton && widget.child != null) {
      return Listener(
        onPointerDown: (_) => setState(() => _rowPressed = true),
        onPointerUp: (_) => setState(() => _rowPressed = false),
        onPointerCancel: (_) => setState(() => _rowPressed = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (details) => _showStandardMenuAt(details.globalPosition),
          child: AnimatedScale(
            scale: _rowPressed ? .985 : 1,
            duration: const Duration(milliseconds: 120),
            child: Material(type: MaterialType.transparency,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                color: _rowPressed ? Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .08) : Colors.transparent,
                child: widget.child)),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: '更多操作',
      onPressed: _toggleGlassMenu,
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

Future<void> showAddToPlaylistSheet(BuildContext context, Track track) async {
  final account = context.read<AccountStore>();
  if (!account.isLoggedIn) {
    context.read<PlayerController>().showNotice('请先登录后再添加到歌单');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      final settings = context.watch<SettingsStore>();
      return KumoneLiquidSurface(radius: 28, interactive: false,
        backingOpacity: settings.menuBackingOpacity, blur: settings.songMenuBlur,
        child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            Container(width: 32, height: 4, decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16), _AddToPlaylistSheet(track: track)])));
    },
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  final Track track;
  const _AddToPlaylistSheet({required this.track});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  bool creating = false;
  final nameController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _createAndAdd() async {
    final name = nameController.text.trim();
    if (name.isEmpty || creating) return;
    final player = context.read<PlayerController>();
    final navigator = Navigator.of(context);
    setState(() => creating = true);
    try {
      final account = context.read<AccountStore>();
      final id = await account.api.createPlaylist(name);
      if (id == null) throw const FormatException('创建歌单失败');
      await account.api.playlistTracks('add', id, [widget.track.id]);
      await account.refreshLibrary();
      if (!mounted) return;
      navigator.pop();
      player.showNotice('已创建歌单并添加歌曲');
    } catch (e) {
      if (mounted) {
        player.showNotice('$e');
      }
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> _add(int playlistId, String name) async {
    final player = context.read<PlayerController>();
    final navigator = Navigator.of(context);
    try {
      final account = context.read<AccountStore>();
      await account.api.playlistTracks('add', playlistId, [widget.track.id]);
      await account.refreshLibrary();
      if (!mounted) return;
      navigator.pop();
      player.showNotice('已添加到「$name」');
    } catch (e) {
      if (mounted) {
        player.showNotice('$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<AccountStore>().createdPlaylists;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('添加到歌单',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(widget.track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (playlists.isEmpty)
              const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('暂无自己创建的歌单，可以直接新建。')),
            ...playlists.map((playlist) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Artwork(
                      url: playlist.coverUrl,
                      size: 46,
                      radius: 8,
                      shadow: false),
                  title: Text(playlist.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${playlist.trackCount} 首'),
                  onTap: () => _add(playlist.id, playlist.name),
                )),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: nameController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _createAndAdd(),
                        decoration: const InputDecoration(
                            labelText: '新建歌单', hintText: '输入歌单名称'))),
                const SizedBox(width: 10),
                IconButton.filled(
                    tooltip: '创建并添加',
                    onPressed: creating ? null : _createAndAdd,
                    icon: creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_rounded)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool showsDate;

  const FeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.imageUrl,
    required this.onTap,
    this.showsDate = false,
  });

  @override
  Widget build(BuildContext context) {
    return KumoneInteractive(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 230,
        height: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 8),
              color: Colors.black.withValues(alpha: .12),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Opacity(
                opacity: .34,
                child: CachedNetworkImage(
                  imageUrl: resizedImageUrl(imageUrl!, 600),
                  fit: BoxFit.cover,
                ),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, color: Colors.white, size: 21),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showsDate)
                    Text(
                      '${DateTime.now().month}月${DateTime.now().day}日',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .78),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Only root tabs opt in: the toolbar scrolls away while categories stay pinned.
class KumoneScrollingTabHeader extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool contentScrolled;
  final double rightInset;
  const KumoneScrollingTabHeader({super.key, required this.title,
    this.actions = const [], this.bottom, this.contentScrolled = false,
    this.rightInset = 8});
  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
    child: SliverPersistentHeader(pinned: true,
      delegate: _TabHeaderDelegate(title, actions, bottom,
        MediaQuery.paddingOf(context).top, contentScrolled, rightInset)));
}
class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final double top;
  final bool contentScrolled;
  final double rightInset;
  _TabHeaderDelegate(this.title, this.actions, this.bottom, this.top,
    this.contentScrolled, this.rightInset);
  @override double get minExtent => top + (bottom?.preferredSize.height ?? 0);
  @override double get maxExtent => minExtent + kToolbarHeight;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / kToolbarHeight).clamp(0.0, 1.0);
    final blurProgress = contentScrolled ? 1.0 : progress;
    return AnnotatedRegion<SystemUiOverlayStyle>(value: kumoneGlassStatusBarStyle(context),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: _KumoneGlassBarSurface(
          followScroll: false, scrollProgress: blurProgress,
          baseHeight: top + 46)),
        Positioned(top: top, left: 16, right: rightInset,
          height: kToolbarHeight * (1 - progress),
          child: IgnorePointer(ignoring: progress >= 1,
            child: ClipRect(child: OverflowBox(alignment: Alignment.bottomCenter,
              minHeight: kToolbarHeight, maxHeight: kToolbarHeight,
              child: Row(children: [Expanded(child: DefaultTextStyle(
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontSize: 26, fontWeight: FontWeight.w800), child: title)), ...actions]))))),
        if (bottom != null) Positioned(left: 0, right: 0, bottom: 0,
          height: bottom!.preferredSize.height, child: bottom!),
      ]));
  }
  @override bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) => true;
}

// Route-local progress: nested horizontal carousels cannot change top chrome.
class KumoneTopBlurScrollScope extends StatefulWidget {
  final Widget child;
  const KumoneTopBlurScrollScope({super.key, required this.child});
  @override
  State<KumoneTopBlurScrollScope> createState() => _TopBlurScrollScopeState();
}
class _TopBlurScrollScopeState extends State<KumoneTopBlurScrollScope> {
  final progress = ValueNotifier<double>(0);
  void update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    progress.value = ((metrics.pixels - metrics.minScrollExtent) /
        kToolbarHeight).clamp(0.0, 1.0);
  }
  @override
  Widget build(BuildContext context) => _TopBlurProgress(notifier: progress,
    child: NotificationListener<ScrollNotification>(
        onNotification: (event) { update(event.metrics, event.depth); return false; },
        child: widget.child));
  @override
  void dispose() { progress.dispose(); super.dispose(); }
}
class _TopBlurProgress extends InheritedNotifier<ValueNotifier<double>> {
  const _TopBlurProgress({required ValueNotifier<double> notifier,
    required super.child}) : super(notifier: notifier);
  static ValueNotifier<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TopBlurProgress>()?.notifier;
}

class KumonePlayAllIcon extends StatelessWidget {
  final double size;
  const KumonePlayAllIcon({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(1, 1), child: Icon(Icons.play_arrow_rounded, size: size));
}
