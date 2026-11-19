import '../widgets/glass_side_navigation.dart';
import '../widgets/wallpaper_scope.dart';
import '../widgets/shell_chrome_transition.dart';
import '../widgets/first_launch_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';
import '../../core/api/netease_api.dart';
import '../../core/storage/account_store.dart';
import '../../core/storage/settings_store.dart';
import '../widgets/common.dart';
import '../widgets/liquid_surface.dart';
import '../widgets/original_player_theme.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';
import 'explore_page.dart';
import 'search_page.dart';
import 'library_page.dart';
import 'now_playing_page.dart';
import 'queue_page.dart';

class _ContentNavigatorObserver extends NavigatorObserver {
  final ValueChanged<bool> onFullscreenChanged;
  final List<Route<dynamic>> _routes = [];

  _ContentNavigatorObserver(this.onFullscreenChanged);

  bool _isFullscreen(Route<dynamic>? route) =>
      route?.settings.name == '/now-playing' ||
      route?.settings.name == '/wallpaper-crop';

  void _sync() {
    // Popups above the player must not bring the mini player back prematurely.
    final page = _routes.whereType<PageRoute<dynamic>>().lastOrNull;
    onFullscreenChanged(_isFullscreen(page));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    if (_isFullscreen(route) && route is TransitionRoute<dynamic>) {
      // Keep shell chrome hidden until the vertically dismissed player is gone.
      route.completed.then((_) => _sync());
    } else {
      _sync();
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _sync();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  bool _init = false;
  final _contentNavigatorKey = GlobalKey<NavigatorState>();
  late final ValueNotifier<int> _tabNotifier = ValueNotifier<int>(0);
  late final NavigatorObserver _contentObserver =
      _ContentNavigatorObserver((hasPushedRoute) {
    if (!mounted) return;
    setState(() => _isNowPlayingFullscreen = hasPushedRoute);
  });
  bool _isNowPlayingFullscreen = false;
  bool _navigationExpanded = true;

  final _pages = const [
    HomePage(),
    ExplorePage(),
    SearchPage(),
    LibraryPage(),
  ];

  static const _labels = ['推荐', '精选', '搜索', '我的'];
  static const _icons = [
    Icons.home_outlined,
    Icons.grid_view_outlined,
    Icons.search,
    Icons.person_outline,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FirstLaunchNotice.showIfNeeded(context);
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final account = context.read<AccountStore>();
    final settings = context.read<SettingsStore>();
    final player = context.read<PlayerController>();
    await NeteaseApi.instance.ensureGuestSession();
    await account.bootstrap();
    await player.setQuality(settings.quality);
    await player.setUnblock(settings.unblock);
    if (mounted) setState(() => _init = true);
  }

  void push(Widget page, {bool fullscreen = false}) =>
      _contentNavigatorKey.currentState?.push(
        kumonePageRoute(
          fullscreen ? OriginalPlayerTheme(child: page) : page,
          settings: RouteSettings(name: fullscreen ? '/now-playing' : null),
        ),
      );

  void _setTab(int index) {
    final navigator = _contentNavigatorKey.currentState;
    // Bottom navigation is the highest-priority navigation surface: any
    // detail page pushed inside the content navigator is dismissed first.
    navigator?.popUntil((route) => route.isFirst);
    if (tab == index) {
      _tabNotifier.value = index;
      return;
    }
    setState(() => tab = index);
    _tabNotifier.value = index;
  }

  @override
  void dispose() {
    _tabNotifier.dispose();
    super.dispose();
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QueuePage(),
    );
  }

  Widget _adaptiveNavigation(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    return KumoneGlassSideNavigation(
      selectedIndex: tab, onChanged: _setTab,
      expanded: _navigationExpanded,
      onExpand: () => setState(() => _navigationExpanded = true),
      onLeft: settings.sideNavigationOnLeft,
      scale: settings.sideNavigationScale,
      position: settings.sideNavigationPosition,
      expandedPosition: settings.sideNavigationExpandedPosition,
      onPositionChanged: (position, onLeft) {
        settings.saveSideNavigationExpandedPosition(position);
        settings.setSideNavigationOnLeft(onLeft);
      },
      order: settings.sideNavigationOrder,
      labels: _labels,
      icons: [for (var i = 0; i < _icons.length; i++)
        tab == i ? _selectedIcon(i) : _icons[i]],
    );
  }

  IconData _selectedIcon(int i) => const [
        Icons.home,
        Icons.grid_view,
        Icons.search,
        Icons.person,
      ][i];

  Widget _miniPlayer(BuildContext context) {
    return Consumer<PlayerController>(
      builder: (_, player, __) {
        final notice = player.sourceNotice;
        if (player.currentTrack == null && notice == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Material(
            color: Colors.transparent,
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (notice != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 6),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KumoneLiquidSurface(
                          key: ValueKey(notice),
                          radius: 999,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          child: Text(
                            notice,
                            style: TextStyle(
                              fontSize: 11,
                              // The notice surface follows the normal theme
                              // surface, so use its foreground instead of the
                              // inverse-surface foreground. In light mode this
                              // keeps the text dark; in dark mode it stays light.
                              color: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (player.currentTrack != null)
                  GlassMiniPlayer(
                    player: player,
                    onOpen: () =>
                        push(const NowPlayingPage(), fullscreen: true),
                    onQueue: () => _showQueue(context),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _transparentBottomNavigation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    // The tab capsule shares the mini player's optical recipe (its tint,
    // blur and refraction), so the two read as one sheet of glass. Only the
    // bar-tuned shape, highlights and contact shadow are kept.
    final barStyle = KumoneGlassOptics.applyTo(
      brightness == Brightness.dark
          ? LiquidGlassTabBar.defaultDarkStyle
          : LiquidGlassTabBar.defaultStyle,
      brightness,
    );
    return SafeArea(
      top: false,
      child: Padding(
        // Keep the shader/view at full available width. Padding the VIEW
        // itself cropped the swollen capsule at its left/right texture edge.
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          // Original layout footprint: preserve both chrome positions and
          // their gap. The full-width shader view retains horizontal headroom.
          height: 74,
          child: LayoutBuilder(builder: (context, constraints) {
            return MediaQuery.removePadding(
              context: context,
              removeBottom: true, // SafeArea above already owns this inset.
              child: LiquidGlassTabBar(
                width: constraints.maxWidth - 28,
                height: 68,
                swell: const LiquidGlassTabBarSwell(),
                margin: EdgeInsets.zero,
                style: barStyle.copyWith(
                    blur: context.watch<SettingsStore>().chromeBlur),
                selectedIndex: tab,
                onChanged: _setTab,
                itemStyle: LiquidGlassTabItemStyle(
                  selectedColor: scheme.primary,
                  unselectedColor: scheme.onSurface,
                  iconSize: 22,
                  underGlassIconSize: 24,
                ),
                items: [
                  for (var i = 0; i < _labels.length; i++)
                    LiquidGlassTabBarItem(
                      icon: _icons[i],
                      selectedIcon: _selectedIcon(i),
                      label: _labels[i],
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _compactBottomLayer(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniPlayer(context),
        _transparentBottomNavigation(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final player = context.watch<PlayerController>();
        final hasTrack = player.currentTrack != null;
        final hasNotice = player.sourceNotice != null;
        // The underlying list must not relayout when the player is dismissed.
        final bottomClearance = wide
            ? (hasTrack ? (hasNotice ? 94.0 : 78.0) : 0.0)
            : (hasTrack ? (hasNotice ? 214.0 : 186.0) : 104.0);
        final wideBottom = _miniPlayer(context);
        return PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            final navigator = _contentNavigatorKey.currentState;
            if (navigator != null && navigator.canPop()) {
              navigator.pop();
              return;
            }
            if (tab != 0) {
              _setTab(0);
              return;
            }
            SystemNavigator.pop();
          },
          child: Scaffold(
            body: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (wide && !_isNowPlayingFullscreen && _navigationExpanded &&
                    notification.metrics.axis == Axis.vertical &&
                    notification.direction == ScrollDirection.reverse) {
                  setState(() => _navigationExpanded = false);
                }
                return false;
              },
              child: Stack(fit: StackFit.expand, children: [
                KumoneBottomOverlayInset(
                  inset: bottomClearance,
                  child: SafeArea(top: false, bottom: false,
                    child: Navigator(
                      key: _contentNavigatorKey,
                      observers: [_contentObserver],
                      onGenerateRoute: (_) => CupertinoPageRoute<void>(
                        builder: (_) => KumoneWallpaperRouteSurface(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _tabNotifier,
                            builder: (_, index, __) => IndexedStack(
                              index: index, children: _pages),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, bottom: 0,
                  child: KumoneShellChromeTransition(
                    visible: !_isNowPlayingFullscreen,
                    child: wide ? wideBottom : _compactBottomLayer(context))),
                if (wide)
                  Positioned.fill(
                    bottom: hasTrack ? (hasNotice ? 102 : 82) : 0,
                    child: KumoneShellChromeTransition(
                      visible: !_isNowPlayingFullscreen,
                      child: _adaptiveNavigation(context))),
              ]),
            ),
            floatingActionButton:
                _init ? null : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
