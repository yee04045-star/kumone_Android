import '../widgets/accent_color_picker.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/liquid_surface.dart';
import 'package:flutter/material.dart';
import 'wallpaper_crop_page.dart';
import 'source_settings_page.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../widgets/common.dart';
import '../widgets/glass_controls.dart';
import '../../core/player/player_controller.dart';
import '../../core/storage/account_store.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/app_icon_store.dart';
import '../../core/storage/wallpaper_store.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  static const MethodChannel _usbChannel = MethodChannel('im.kumone.audio/usb');

  static void _moveNavigation(SettingsStore settings, int index, int delta) {
    final order = List<int>.of(settings.sideNavigationOrder);
    final item = order.removeAt(index);
    order.insert(index + delta, item);
    settings.setSideNavigationOrder(order);
  }

  final String? category;
  const SettingsPage({super.key, this.category});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final account = context.read<AccountStore>();
    final player = context.read<PlayerController>();
    final baseTheme = Theme.of(context);
    final blue = baseTheme.colorScheme.primary;
    final mutedBlue = blue.withValues(alpha: .28);
    final disabled = baseTheme.colorScheme.onSurface.withValues(alpha: .38);
    final blueControlColor = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return disabled;
      if (states.contains(WidgetState.selected) ||
          states.contains(WidgetState.pressed)) {
        return blue;
      }
      return null;
    });

    return Theme(
      data: baseTheme.copyWith(
        // Keep blue as an interaction accent, not a global surface color.
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return blue.withValues(alpha: .28);
              }
              return blue;
            }),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return blue.withValues(alpha: .28);
              }
              return blue;
            }),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: blueControlColor,
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return BorderSide(color: disabled.withValues(alpha: .16));
              }
              return BorderSide(color: blue.withValues(alpha: .46));
            }),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return disabled;
              return blue;
            }),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return disabled;
            if (states.contains(WidgetState.selected)) return blue;
            return null;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            final disabledState = states.contains(WidgetState.disabled);
            if (disabledState) return disabled.withValues(alpha: .10);
            if (selected) return mutedBlue;
            return baseTheme.colorScheme.surfaceContainerHighest;
          }),
          trackOutlineColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return blue.withValues(alpha: .34);
            }
            return baseTheme.colorScheme.outlineVariant;
          }),
        ),
        radioTheme: RadioThemeData(fillColor: blueControlColor),
        sliderTheme: baseTheme.sliderTheme.copyWith(
          activeTrackColor: blue,
          thumbColor: blue,
          overlayColor: blue.withValues(alpha: .10),
        ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: KumoneGlassAppBar(title: category == null ? const Text('设置') : const SizedBox.shrink()),
        body: ListView(
          padding: EdgeInsets.only(
              top: kumoneToolbarInset(context),
              bottom: KumoneBottomOverlayInset.of(context) + 24),
          children: _categorized(context, [
            ...[
              const _SettingsHeader('自定义背景'),
              Consumer<WallpaperStore>(
                  builder: (context, wallpaper, _) => Column(children: [
                        for (final landscape in [false, true])
                        ListTile(
                            leading: Icon(landscape ? Icons.stay_current_landscape : Icons.stay_current_portrait),
                            title: Text(landscape ? '选择横屏壁纸' : '选择竖屏壁纸'),
                            subtitle: Text(wallpaper.pathFor(landscape) != null ? '已设置 · 点击重新选择并裁切' : '未设置 · 此方向使用默认背景'),
                            onTap: () async {
                              try {
                                await wallpaper.pick(landscape: landscape, crop: (bytes) async {
                                  if (!context.mounted) return null;
                                  final size = MediaQuery.sizeOf(context);
                                  return Navigator.of(context).push<Uint8List>(kumonePageRoute(
                                    WallpaperCropPage(bytes: bytes, aspectRatio: landscape
                                      ? size.longestSide / size.shortestSide : size.shortestSide / size.longestSide),
                                    settings: const RouteSettings(name: '/wallpaper-crop')));
                                });
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('设置背景失败：$e')));
                                }
                              }
                            }),
                        if (wallpaper.enabled || wallpaper.landscapePath != null) ...[
                          ListTile(
                              title: const Text('背景模糊'),
                              trailing: Text('${wallpaper.blur.round()}')),
                          KumoneGlassSlider(
                              value: wallpaper.blur,
                              max: 40,
                              onChanged: wallpaper.previewBlur,
                              onChangeEnd: wallpaper.saveBlur),
                          for (final landscape in [false, true])
                            if (wallpaper.pathFor(landscape) != null)
                              TextButton(onPressed: () => wallpaper.clear(landscape: landscape),
                                child: Text(landscape ? '移除横屏壁纸' : '移除竖屏壁纸')),
                        ],
                      ])),

              const Divider(height: 24),
              const _SettingsHeader('应用图标与启动屏'),
              Consumer<AppIconStore>(
                  builder: (context, icons, _) => Column(
                        children: [
                          const ListTile(
                              subtitle:
                                  Text('桌面图标与开屏图标绑定切换。部分桌面可能延迟刷新；从下次冷启动生效。')),
                          for (final choice in icons.visibleChoices)
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(choice.asset,
                                    width: 48, height: 48),
                              ),
                              title: Text(choice.label),
                              trailing: icons.selected == choice
                                  ? Icon(Icons.check_circle,
                                      color: blue)
                                  : null,
                              enabled: !icons.busy,
                              onTap: () async {
                                try {
                                  await icons.select(choice);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('图标切换失败：$e')));
                                  }
                                }
                              },
                            ),
                        ],
                      )),
              const Divider(height: 24),
              const _SettingsHeader('外观'),
              const ListTile(title: Text('主题强调色')),
              for (final accent in AppAccent.values.where((accent) => accent != AppAccent.spotifyGreen && accent != AppAccent.qqGreen && accent != AppAccent.neteaseRed))
                _CheckChoice(selected: settings.customAccent == null && settings.accent == accent,
                  title: accent.label,
                  onTap: () => settings.setAccent(accent)),
              ListTile(title: const Text('自定义颜色'),
                leading: CircleAvatar(radius: 12, backgroundColor: settings.accentColor),
                trailing: settings.customAccent != null ? const Icon(Icons.check) : null,
                onTap: () async {
                  final color = await kumoneDialog<Color>(context: context,
                    builder: (_) => AccentColorPicker(initial: settings.accentColor));
                  if (color != null) await settings.setCustomAccent(color);
                }),
              RadioGroup<AppearanceMode>(
                groupValue: settings.appearance,
                onChanged: (value) {
                  if (value != null) {
                    settings.setAppearance(value);
                  }
                },
                child: Column(
                  children: [
                    for (final mode in AppearanceMode.values)
                      _CheckChoice(title: _appearanceLabel(mode),
                        selected: settings.appearance == mode,
                        onTap: () => settings.setAppearance(mode)),
                  ],
                ),
              ),
              const Divider(height: 24),
              const _SettingsHeader('顶部渐变模糊'),
              ListTile(title: const Text('顶部模糊渐变范围'),
                subtitle: const Text('从状态栏向下的作用距离；仅延长模糊绘制，不改变顶栏和内容布局'),
                trailing: Text('${(settings.topBlurExtent * 100).round()}%')),
              KumoneGlassSlider(value: settings.topBlurExtent, min: .75, max: 3,
                onChanged: settings.previewTopBlurExtent,
                onChangeEnd: settings.saveTopBlurExtent),
              Align(alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => settings.saveTopBlurExtent(1),
                  child: const Text('恢复默认渐变范围'))),
              ListTile(
                title: const Text('顶部模糊渐变分布'),
                subtitle: const Text('渐清更快 ← → 渐清更慢\n向右让标题、分类区域保留更多模糊，不增加模糊强度或底色厚度'),
                trailing: Text('${settings.topBlurDistribution.toStringAsFixed(2)}×'),
              ),
              KumoneGlassSlider(
                value: settings.topBlurDistribution,
                min: .5, max: 6,
                onChanged: settings.previewTopBlurDistribution,
                onChangeEnd: settings.saveTopBlurDistribution,
              ),
              Align(alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => settings.saveTopBlurDistribution(1),
                  child: const Text('恢复默认渐变分布'))),
              const Divider(height: 24),
              const _SettingsHeader('歌曲菜单 · 液态玻璃'),

              ListTile(
                title: const Text('二级菜单与快捷入口底色不透明度'),
                subtitle: const Text('菜单、快捷入口、搜索框及收藏关注按钮共用；不影响底栏与 mini 播放器'),
                trailing:
                    Text('${(settings.menuBackingOpacity * 100).round()}%'),
              ),
              KumoneGlassSlider(
                value: settings.menuBackingOpacity,
                label: '${(settings.menuBackingOpacity * 100).round()}%',
                onChanged: settings.previewMenuBackingOpacity,
                onChangeEnd: settings.saveMenuBackingOpacity,
              ),
              const Divider(height: 24),
              ListTile(title: const Text('Tab 栏与 mini 播放器 · 底色不透明度'),
                trailing: Text('${((settings.chromeBackingOpacity ?? KumoneGlassOptics.backingOpacity(Theme.of(context).brightness)) * 100).round()}%')),
              KumoneGlassSlider(value: settings.chromeBackingOpacity ?? KumoneGlassOptics.backingOpacity(Theme.of(context).brightness),
                min: 0, max: 1, onChanged: settings.previewChromeBackingOpacity,
                onChangeEnd: settings.saveChromeBackingOpacity),
              ListTile(
                title: const Text('菜单、控件、底栏与 mini · 模糊强度'),
                trailing: Text(settings.songMenuBlur.toStringAsFixed(1)),
              ),
              KumoneGlassSlider(value: settings.songMenuBlur, max: 40,
                onChanged: settings.previewSongMenuBlur,
                onChangeEnd: settings.saveSongMenuBlur),
              ListTile(title: const Text('我的快捷入口 · 模糊强度'),
                subtitle: const Text('独立调节；底色不透明度仍与菜单共用'),
                trailing: Text(settings.quickEntryBlur.toStringAsFixed(1))),
              KumoneGlassSlider(value: settings.quickEntryBlur, max: 40,
                onChanged: settings.previewQuickEntryBlur,
                onChangeEnd: settings.saveQuickEntryBlur),
              const Divider(height: 24),
              const _SettingsHeader('横屏 / 平板 · 浮动功能栏'),
              KumoneGlassSwitchTile(
                title: const Text('双击状态栏回顶'),
                subtitle: const Text('仅当前页面回顶；部分 Android 设备会被系统拦截，可能不生效'),
                value: settings.statusBarDoubleTapToTop,
                onChanged: settings.setStatusBarDoubleTapToTop),
              ListTile(title: const Text('mini 播放器与 Tab 间距'),
                subtitle: const Text('按 1206px 参考截图比例：24～36px'),
                trailing: Text('${settings.miniTabGap.round()}px')),
              KumoneGlassSlider(value: settings.miniTabGap, min: 24, max: 36,
                onChanged: settings.previewMiniTabGap,
                onChangeEnd: settings.saveMiniTabGap),

              ListTile(title: const Text('底栏与 mini 播放器 · 纵向位置'),
                subtitle: const Text('向左上移，向右下移；下移最多 6，保留系统导航安全间距'),
                trailing: Text(settings.bottomChromeOffset.toStringAsFixed(0))),
              KumoneGlassSlider(value: settings.bottomChromeOffset, min: -24, max: 6,
                onChanged: settings.previewBottomChromeOffset,
                onChangeEnd: settings.saveBottomChromeOffset),




              KumoneGlassSwitchTile(
                title: const Text('功能栏位于左侧'),
                subtitle: const Text('关闭时位于右侧；搜索始终单独显示'),
                value: settings.sideNavigationOnLeft,
                onChanged: settings.setSideNavigationOnLeft),
              ListTile(title: const Text('功能栏大小'),
                trailing: Text('${(settings.sideNavigationScale * 100).round()}%')),
              KumoneGlassSlider(value: settings.sideNavigationScale,
                min: .8, max: 1.4,
                onChanged: settings.previewSideNavigationScale,
                onChangeEnd: settings.saveSideNavigationScale),
              ListTile(title: const Text('收缩后搜索按钮 · 纵向位置'),
                subtitle: const Text('仅调整收缩后的搜索按钮；展开的功能栏长按 1 秒后可拖动位置'),
                trailing: Text('${(settings.sideNavigationPosition * 100).round()}%')),
              KumoneGlassSlider(value: settings.sideNavigationPosition,
                onChanged: settings.previewSideNavigationPosition,
                onChangeEnd: settings.saveSideNavigationPosition),
              const ListTile(title: Text('底部 Tab 顺序（从左到右）')),
              for (var position = 0; position < 4; position++) ListTile(
                title: Text(const ['推荐', '精选', '搜索', '我的'][settings.bottomTabOrder[position]]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final delta in [-1, 1]) IconButton(
                    icon: RotatedBox(quarterTurns: delta < 0 ? 0 : 2, child: const Icon(CupertinoIcons.chevron_back)),
                    onPressed: position + delta < 0 || position + delta > 3 ? null : () {
                      final order = List<int>.of(settings.bottomTabOrder);
                      final item = order.removeAt(position);
                      order.insert(position + delta, item);
                      settings.setBottomTabOrder(order);
                    }),
                ])),
              const ListTile(title: Text('功能顺序（从上到下）'),
                subtitle: Text('使用上移 / 下移调整，搜索不参与排序')),
              for (var position = 0; position < settings.sideNavigationOrder.length; position++)
                ListTile(
                  title: Text(const ['推荐', '精选', '搜索', '我的'][settings.sideNavigationOrder[position]]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: '上移', icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: position == 0 ? null : () => _moveNavigation(settings, position, -1)),
                    IconButton(tooltip: '下移', icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: position == 2 ? null : () => _moveNavigation(settings, position, 1)),
                  ]),
                ),
            ],
            ...[
              const _SettingsHeader('播放音质'),
              RadioGroup<String>(
                groupValue: settings.quality,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  settings.setQuality(value);
                  player.quality = value;
                  player.handler.setQuality(value);
                },
                child: Column(
                  children: [
                    for (final quality in const [
                      'standard',
                      'higher',
                      'exhigh',
                      'lossless',
                      'hires',
                    ])
                      _CheckChoice(title: _qualityLabel(quality),
                        selected: settings.quality == quality,
                        onTap: () {
                          settings.setQuality(quality);
                          player.quality = quality;
                          player.handler.setQuality(quality);
                        }),
                  ],
                ),
              ),
              const Divider(height: 24),
              const _SettingsHeader('淡入/淡出'),
              ListTile(
                  title: const Text('曲目重叠过渡时长'),
                  subtitle: Text(settings.usbExclusive
                      ? '独占 USB 模式不混音，暂不启用重叠'
                      : '0 秒关闭；自动切歌使用等功率交叉淡化'),
                  trailing: Text('${settings.crossfadeSeconds} 秒')),
              KumoneGlassSlider(
                  value: settings.crossfadeSeconds.toDouble(),
                  max: 12,
                  onChanged: settings.previewCrossfade,
                  onChangeEnd: settings.saveCrossfade),
              const _SettingsHeader('音频输出'),
              KumoneGlassSwitchTile(
                value: settings.usbExclusive,
                onChanged: (value) =>
                    _setUsbExclusive(context, settings, value),
                title: const Text('独占 USB'),
                subtitle: const Text('连接兼容的 USB DAC 后绕过系统混音；Android 14+'),
              ),
              const Divider(height: 24),
              const _SettingsHeader('存储'),
              KumoneGlassSwitchTile(title: const Text('列表按需加载'),
                subtitle: const Text('开启后减少屏幕外封面预加载；关闭时提前准备附近内容，优先保证滑动流畅。不会预加载歌曲音频'),
                value: settings.listLazyLoading,
                onChanged: settings.setListLazyLoading),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清理缓存'),
                subtitle: const Text('删除预加载和第三方音源缓存，不影响登录和设置'),
                onTap: () => _confirmClearCache(context, player),
              ),
              const Divider(height: 24),
            ],
            ...[
              const _SettingsHeader('播放页'),
              RadioGroup<NowPlayingMode>(
                groupValue: settings.nowPlaying,
                onChanged: (value) {
                  if (value != null) settings.setNowPlaying(value);
                },
                child: Column(
                  children: [
                    for (final mode in NowPlayingMode.values)
                      _CheckChoice(selected: settings.nowPlaying == mode,
                        onTap: () => settings.setNowPlaying(mode),
                        title: switch (mode) {
                          NowPlayingMode.immersive => '沉浸模式',
                          NowPlayingMode.minimal => '简洁模式',
                        }),
                  ],
                ),
              ),

              const Divider(height: 24),
              const _SettingsHeader('横屏与歌词效果'),
              ListTile(
                title: const Text('大播放页歌词字号'),
                subtitle: const Text('80%～180% 无极调节；100% 为原来的默认字号，翻译与注音同比缩放'),
                trailing: Text('${(settings.lyricFontScale * 100).round()}%'),
              ),
              KumoneGlassSlider(value: settings.lyricFontScale,
                min: .8, max: 1.8,
                onChanged: settings.previewLyricFontScale,
                onChangeEnd: settings.saveLyricFontScale),
              Align(alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => settings.saveLyricFontScale(1),
                  child: const Text('恢复默认字号'))),

              ListTile(
                  title: const Text('双向歌词模糊强度'),
                  subtitle: const Text('当前行保持清晰；设为 0 关闭'),
                  trailing: Text(settings.lyricBlur.toStringAsFixed(1))),
              KumoneGlassSlider(
                  value: settings.lyricBlur,
                  max: 8,
                  onChanged: settings.previewLyricBlur,
                  onChangeEnd: settings.saveLyricBlur),
              KumoneGlassSwitchTile(
                  value: settings.cjkGlow,
                  onChanged: settings.setCjkGlow,
                  title: const Text('CJK 长尾歌词辉光'),
                  subtitle: const Text('逐字歌词的中日韩长音渐亮渐隐')),
              const _SettingsHeader('歌词'),
              KumoneGlassSwitchTile(
                value: settings.translation,
                onChanged: settings.setTranslation,
                title: const Text('显示歌词翻译'),
              ),
              KumoneGlassSwitchTile(title: const Text('逐词歌词高亮'),
                value: settings.verbatim, onChanged: settings.setVerbatim),
              RadioGroup<LyricsAnnotationMode>(
                groupValue: settings.annotation,
                onChanged: (value) {
                  if (value != null) settings.setLyricsAnnotation(value);
                },
                child: Column(
                  children: [
                    for (final mode in LyricsAnnotationMode.values)
                      _CheckChoice(selected: settings.annotation == mode,
                        onTap: () => settings.setLyricsAnnotation(mode),
                        title: switch (mode) {
                          LyricsAnnotationMode.off => '日文读音：关闭',
                          LyricsAnnotationMode.romaji => '日文读音：罗马音',
                          LyricsAnnotationMode.furigana => '日文读音：汉字注音',
                        }),
                  ],
                ),
              ),
            ],
            ...[
              const _SettingsHeader('补源与账户'),
              ListTile(leading: const Icon(Icons.settings_input_component),
                title: const Text('音源配置'), subtitle: const Text('添加、启停及排序 · 最多 7 个自定义音源'),
                trailing: const KumoneForwardChevron(),
                onTap: () => Navigator.of(context).push(kumonePageRoute(const SourceSettingsPage(), settings: const RouteSettings(name: '/settings')))),
              KumoneGlassSwitchTile(
                value: settings.unblock,
                onChanged: (value) {
                  settings.setUnblock(value);
                  player.unblock = value;
                  player.handler.setUnblock(value);
                },
                title: const Text('启用自定义音源补源'),
                subtitle: const Text('官方音源不可用时，依次尝试配置中已启用的音源'),
              ),
              if (account.isLoggedIn)
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('退出登录'),
                  onTap: account.logout,
                ),
              const ListTile(
                title: Text('关于 Kumone'),
                subtitle: Text('Flutter Android 重构版 · Android 14+'),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  List<Widget> _categorized(BuildContext context, List<Widget> items) {
    const groups = <String, String>{
      '自定义背景': '背景与外观', '应用图标与启动屏': '背景与外观',
      '外观': '背景与外观', '顶部渐变模糊': '玻璃与模糊',
      '歌曲菜单 · 液态玻璃': '玻璃与模糊',
      '横屏 / 平板 · 浮动功能栏': '浮动功能栏',
      '播放音质': '音频与播放', '淡入/淡出': '音频与播放',
      '音频输出': '音频与播放', '存储': '存储与账户',
      '补源与账户': '存储与账户',
      '播放页': '播放页', '横屏与歌词效果': '播放页',
      '歌词': '播放页',
    };
    final sections = <String, List<Widget>>{};
    var current = '存储与账户';
    for (final item in items) {
      if (item is _SettingsHeader) current = groups[item.title] ?? current;
      (sections[current] ??= []).add(item);
    }
    if (category != null) return sections[category] ?? [];
    return [for (final name in sections.keys) Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: .16), width: .5))),
      child: ListTile(
      title: Text(name), trailing: const KumoneForwardChevron(),
      onTap: () => Navigator.of(context).push(kumonePageRoute(SettingsPage(category: name), settings: const RouteSettings(name: '/settings'))),
    ))];
  }

  Future<void> _confirmClearCache(
    BuildContext context,
    PlayerController player,
  ) async {
    final confirmed = await kumoneDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将删除已经下载的预加载音频和第三方音源缓存。当前正在播放的本地音频会保留，以免中断播放。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await player.handler.clearAudioCache();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清理')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存清理失败')),
      );
    }
  }

  Future<void> _setUsbExclusive(
    BuildContext context,
    SettingsStore settings,
    bool value,
  ) async {
    if (!value) {
      try {
        await _usbChannel.invokeMethod<bool>(
          'setUsbExclusive',
          {'enabled': false},
        );
      } catch (_) {}
      await settings.setUsbExclusive(false);
      return;
    }

    try {
      final result = await _usbChannel.invokeMethod<Map<dynamic, dynamic>>(
        'setUsbExclusive',
        {'enabled': true},
      );
      final applied = result?['applied'] == true;
      if (applied) {
        await settings.setUsbExclusive(true);
        if (context.mounted) {
          final pendingPermission = result?['pendingPermission'] == true;
          final message = result?['message']?.toString() ??
              (pendingPermission ? '请允许 USB 设备访问' : '独占 USB 已开启（USB 直连模式）');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
        return;
      }

      await settings.setUsbExclusive(false);
      if (context.mounted) {
        final message = result?['message']?.toString() ?? '未检测到兼容的 USB 音频设备';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      await settings.setUsbExclusive(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前设备不支持独占 USB')),
        );
      }
    }
  }

  String _appearanceLabel(AppearanceMode mode) {
    switch (mode) {
      case AppearanceMode.system:
        return '跟随系统';
      case AppearanceMode.light:
        return '浅色';
      case AppearanceMode.dark:
        return '深色';
    }
  }

  String _qualityLabel(String quality) {
    switch (quality) {
      case 'standard':
        return '标准';
      case 'higher':
        return '较高';
      case 'exhigh':
        return '极高';
      case 'lossless':
        return '无损';
      default:
        return 'Hi-Res';
    }
  }
}

class _CheckChoice extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;
  const _CheckChoice({required this.title, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(selected: selected,
    child: ListTile(title: Text(title), onTap: onTap,
      trailing: selected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null));
}

class _SettingsHeader extends StatelessWidget {
  final String title;
  const _SettingsHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
