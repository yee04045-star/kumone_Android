import 'app_accent.dart';
export 'app_accent.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppearanceMode { system, light, dark }

enum NowPlayingMode { immersive, minimal }

enum LyricsAnnotationMode { off, romaji, furigana }

class SettingsStore extends ChangeNotifier {
  final prefs = SharedPreferencesAsync();
  bool statusBarDoubleTapToTop = true;
  Future<void> setStatusBarDoubleTapToTop(bool value) async {
    statusBarDoubleTapToTop = value;
    notifyListeners();
    await prefs.setBool('statusBarDoubleTapToTop', value);
  }

  AppAccent accent = AppAccent.appleBlue;
  AppearanceMode appearance = AppearanceMode.system;
  NowPlayingMode nowPlaying = NowPlayingMode.immersive;
  String quality = 'exhigh';
  bool translation = true;
  bool verbatim = true;
  LyricsAnnotationMode annotation = LyricsAnnotationMode.off;
  bool unblock = true;
  bool ambient = true;
  bool freezeOutgoingPage = true;
  bool usbExclusive = false;
  double ambientIntensity = 1.0;
  double menuBackingOpacity = .50;
  bool landscapeDualPane = true;
  double lyricBlur = 5;
  double lyricFontScale = 1.1;
  bool cjkGlow = true;
  int crossfadeSeconds = 0;
  // Whether the app background (including a custom wallpaper) is allowed to
  // run behind the status bar. The now-playing page ignores this and always
  // uses its own ambient system-bar treatment.
  bool backgroundExtend = true;
  double chromeBlur = 5;
  double? chromeBackingOpacity;
  void previewChromeBackingOpacity(double value) {
    chromeBackingOpacity = value.clamp(0, 1).toDouble();
    notifyListeners();
  }
  Future<void> saveChromeBackingOpacity(double value) async {
    previewChromeBackingOpacity(value);
    await prefs.setDouble('chromeBackingOpacity', chromeBackingOpacity!);
  }
  double bottomChromeOffset = 6;
  double miniTabGap = 24;
  void previewMiniTabGap(double value) {
    miniTabGap = value.clamp(24, 36).toDouble();
    notifyListeners();
  }
  Future<void> saveMiniTabGap(double value) async {
    previewMiniTabGap(value);
    await prefs.setDouble('miniTabGap', miniTabGap);
  }
  double topBlurDistribution = 1.20;
  double topBlurExtent = 1.20;
  double songMenuBlur = 3;
  bool songMenuFocus = true;
  double quickEntryBlur = 3;
  double sideNavigationScale = 1;
  double sideNavigationPosition = .8;
  double sideNavigationExpandedPosition = .8;
  bool sideNavigationOnLeft = false;
  List<int> bottomTabOrder = [0, 1, 2, 3];
  Future<void> setBottomTabOrder(List<int> order) async {
    if (order.length != 4 || order.toSet().length != 4 ||
        !order.every((i) => i >= 0 && i < 4)) { return; }
    bottomTabOrder = List.of(order);
    notifyListeners();
    await prefs.setStringList('bottomTabOrder', order.map((i) => '$i').toList());
  }
  List<int> sideNavigationOrder = [3, 1, 0];

  Future<void> setFreezeOutgoingPage(bool value) async {
    freezeOutgoingPage = value;
    notifyListeners();
    await prefs.setBool('freezeOutgoingPage', value);
  }

  void previewBottomChromeOffset(double value) {
    bottomChromeOffset = value.clamp(-24, 6).toDouble();
    notifyListeners();
  }
  Future<void> saveBottomChromeOffset(double value) async {
    previewBottomChromeOffset(value);
    await prefs.setDouble('bottomChromeOffset', bottomChromeOffset);
  }

  Future<void> load() async {
    statusBarDoubleTapToTop = await prefs.getBool('statusBarDoubleTapToTop') ?? true;
    final tabs = (await prefs.getStringList('bottomTabOrder'))?.map(int.tryParse)
        .whereType<int>().toList();
    if (tabs != null && tabs.length == 4 && tabs.toSet().length == 4 &&
        tabs.every((i) => i >= 0 && i < 4)) { bottomTabOrder = tabs; }
    chromeBackingOpacity = (await prefs.getDouble('chromeBackingOpacity') ??
        await prefs.getDouble('tabBackingOpacity') ??
        await prefs.getDouble('miniBackingOpacity'))?.clamp(0, 1).toDouble();
    miniTabGap = (await prefs.getDouble('miniTabGap') ?? 24).clamp(24, 36).toDouble();
    bottomChromeOffset = (await prefs.getDouble('bottomChromeOffset') ?? 6).clamp(-24, 6).toDouble();
    freezeOutgoingPage = true;
    final accentName = await prefs.getString('appAccent');
    accent = AppAccent.values.firstWhere((e) => e.name == accentName,
      orElse: () => AppAccent.appleBlue);
    final appearanceName = await prefs.getString('appearance') ?? 'system';
    appearance = AppearanceMode.values.firstWhere(
      (e) => e.name == appearanceName,
      orElse: () => AppearanceMode.system,
    );
    final nowPlayingName = await prefs.getString('nowPlaying') ?? 'immersive';
    nowPlaying = NowPlayingMode.values.firstWhere(
      (e) => e.name == nowPlayingName,
      orElse: () => NowPlayingMode.immersive,
    );
    quality = await prefs.getString('quality') ?? 'exhigh';
    translation = await prefs.getBool('translation') ?? true;
    verbatim = await prefs.getBool('verbatim') ?? true;
    final annotationName = await prefs.getString('lyricsAnnotation') ?? 'off';
    annotation = LyricsAnnotationMode.values.firstWhere(
      (e) => e.name == annotationName,
      orElse: () => LyricsAnnotationMode.off,
    );
    unblock = await prefs.getBool('unblock') ?? true;
    ambient = true;
    usbExclusive = await prefs.getBool('usbExclusive') ?? false;
    ambientIntensity = await prefs.getDouble('ambientIntensity') ?? 1.0;
    menuBackingOpacity = ((await prefs.getDouble('menuBackingOpacity')) ?? .50)
        .clamp(0.0, 1.0)
        .toDouble();
    landscapeDualPane = true;
    lyricBlur =
        (await prefs.getDouble('lyricBlur') ?? 5).clamp(0, 8).toDouble();
    lyricFontScale = (await prefs.getDouble('lyricFontScale') ?? 1.1)
        .clamp(.8, 1.8).toDouble();
    cjkGlow = await prefs.getBool('cjkGlow') ?? true;
    crossfadeSeconds = (await prefs.getInt('crossfadeSeconds') ?? 0).clamp(0, 12);
    backgroundExtend = true;
    chromeBlur =
        (await prefs.getDouble('chromeBlur') ?? 5).clamp(0, 40).toDouble();
    topBlurExtent = (await prefs.getDouble('topBlurExtent') ?? 1.20)
        .clamp(.75, 3).toDouble();
    topBlurDistribution =
        (await prefs.getDouble('topBlurDistribution') ?? 1.20).clamp(.5, 6).toDouble();
    songMenuFocus = true;
    quickEntryBlur = (await prefs.getDouble('quickEntryBlur') ?? 3).clamp(0, 40).toDouble();
    songMenuBlur = (await prefs.getDouble('songMenuBlur') ??
        await prefs.getDouble('chromeBlur') ?? 3).clamp(0, 40).toDouble();
    chromeBlur = songMenuBlur;

    sideNavigationScale = (await prefs.getDouble('sideNavigationScale') ?? 1)
        .clamp(.8, 1.4).toDouble();
    sideNavigationPosition = (await prefs.getDouble('sideNavigationPosition') ?? .8)
        .clamp(0, 1).toDouble();
    sideNavigationExpandedPosition =
        (await prefs.getDouble('sideNavigationExpandedPosition') ?? .8)
            .clamp(0, 1).toDouble();
    sideNavigationOnLeft = await prefs.getBool('sideNavigationOnLeft') ?? false;
    final order = (await prefs.getStringList('sideNavigationOrder'))
        ?.map(int.tryParse).whereType<int>().toList();
    if (order != null && _validSideOrder(order)) sideNavigationOrder = order;
    notifyListeners();
  }

  void previewCrossfade(double value) {
    crossfadeSeconds = value.round().clamp(0, 12); notifyListeners();
  }
  Future<void> saveCrossfade(double value) async {
    previewCrossfade(value); await prefs.setInt('crossfadeSeconds', crossfadeSeconds);
  }

  Future<void> setLandscapeDualPane(bool value) async {
    landscapeDualPane = value;
    notifyListeners();
    await prefs.setBool('landscapeDualPane', value);
  }

  void previewLyricFontScale(double value) {
    lyricFontScale = value.clamp(.8, 1.8).toDouble();
    notifyListeners();
  }

  Future<void> saveLyricFontScale(double value) async {
    previewLyricFontScale(value);
    await prefs.setDouble('lyricFontScale', lyricFontScale);
  }

  void previewLyricBlur(double value) {
    lyricBlur = value.clamp(0, 8).toDouble();
    notifyListeners();
  }

  Future<void> saveLyricBlur(double value) async {
    previewLyricBlur(value);
    await prefs.setDouble('lyricBlur', lyricBlur);
  }

  Future<void> setCjkGlow(bool value) async {
    cjkGlow = value;
    notifyListeners();
    await prefs.setBool('cjkGlow', value);
  }

  Future<void> setBackgroundExtend(bool value) async {
    backgroundExtend = value;
    notifyListeners();
    await prefs.setBool('backgroundExtend', value);
  }

  void previewTopBlurExtent(double value) {
    if (!value.isFinite) return;
    topBlurExtent = value.clamp(.75, 3).toDouble();
    notifyListeners();
  }

  Future<void> saveTopBlurExtent(double value) async {
    previewTopBlurExtent(value);
    await prefs.setDouble('topBlurExtent', topBlurExtent);
  }

  void previewTopBlurDistribution(double value) {
    if (!value.isFinite) return;
    topBlurDistribution = value.clamp(.5, 6).toDouble();
    notifyListeners();
  }

  Future<void> saveTopBlurDistribution(double value) async {
    previewTopBlurDistribution(value);
    await prefs.setDouble('topBlurDistribution', topBlurDistribution);
  }

  void previewChromeBlur(double value) {
    chromeBlur = value.clamp(0, 40).toDouble();
    songMenuBlur = chromeBlur;
    notifyListeners();
  }

  Future<void> saveChromeBlur(double value) async {
    previewChromeBlur(value);
    await prefs.setDouble('chromeBlur', chromeBlur);
    await prefs.setDouble('songMenuBlur', chromeBlur);
  }

  Future<void> setAccent(AppAccent value) async {
    accent = value;
    notifyListeners();
    await prefs.setString('appAccent', value.name);
  }

  Future<void> setSongMenuFocus(bool value) async {
    songMenuFocus = value;
    notifyListeners();
    await prefs.setBool('songMenuFocus', value);
  }

  void previewSongMenuBlur(double value) {
    songMenuBlur = value.clamp(0, 40).toDouble();
    chromeBlur = songMenuBlur;
    notifyListeners();
  }

  Future<void> saveSongMenuBlur(double value) async {
    previewSongMenuBlur(value);
    await prefs.setDouble('songMenuBlur', songMenuBlur);
    await prefs.setDouble('chromeBlur', songMenuBlur);
  }

  void previewQuickEntryBlur(double value) {
    quickEntryBlur = value.clamp(0, 40).toDouble();
    notifyListeners();
  }
  Future<void> saveQuickEntryBlur(double value) async {
    previewQuickEntryBlur(value);
    await prefs.setDouble('quickEntryBlur', quickEntryBlur);
  }


  void previewSideNavigationScale(double value) {
    sideNavigationScale = value.clamp(.8, 1.4).toDouble();
    notifyListeners();
  }

  Future<void> saveSideNavigationScale(double value) async {
    previewSideNavigationScale(value);
    await prefs.setDouble('sideNavigationScale', sideNavigationScale);
  }

  void previewSideNavigationPosition(double value) {
    sideNavigationPosition = value.clamp(0, 1).toDouble();
    notifyListeners();
  }

  Future<void> saveSideNavigationPosition(double value) async {
    previewSideNavigationPosition(value);
    await prefs.setDouble('sideNavigationPosition', sideNavigationPosition);
  }

  Future<void> saveSideNavigationExpandedPosition(double value) async {
    sideNavigationExpandedPosition = value.clamp(0, 1).toDouble();
    notifyListeners();
    await prefs.setDouble('sideNavigationExpandedPosition', sideNavigationExpandedPosition);
  }

  Future<void> setSideNavigationOnLeft(bool value) async {
    sideNavigationOnLeft = value;
    notifyListeners();
    await prefs.setBool('sideNavigationOnLeft', value);
  }

  static bool _validSideOrder(List<int> order) =>
      order.length == 3 && order.toSet().containsAll([0, 1, 3]);

  Future<void> setSideNavigationOrder(List<int> order) async {
    if (!_validSideOrder(order)) return;
    sideNavigationOrder = List.of(order);
    notifyListeners();
    await prefs.setStringList('sideNavigationOrder',
        sideNavigationOrder.map((i) => '$i').toList());
  }

  void previewMenuBackingOpacity(double value) {
    menuBackingOpacity = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  Future<void> saveMenuBackingOpacity(double value) async {
    previewMenuBackingOpacity(value);
    await prefs.setDouble('menuBackingOpacity', menuBackingOpacity);
  }

  Future<void> setAppearance(AppearanceMode value) async {
    appearance = value;
    await prefs.setString('appearance', value.name);
    notifyListeners();
  }

  Future<void> setNowPlaying(NowPlayingMode value) async {
    nowPlaying = value;
    await prefs.setString('nowPlaying', value.name);
    notifyListeners();
  }

  Future<void> setQuality(String value) async {
    quality = value;
    await prefs.setString('quality', value);
    notifyListeners();
  }

  Future<void> setTranslation(bool value) async {
    translation = value;
    await prefs.setBool('translation', value);
    notifyListeners();
  }

  Future<void> setLyricsAnnotation(LyricsAnnotationMode value) async {
    annotation = value;
    await prefs.setString('lyricsAnnotation', value.name);
    notifyListeners();
  }

  Future<void> setVerbatim(bool value) async {
    verbatim = value;
    await prefs.setBool('verbatim', value);
    notifyListeners();
  }

  Future<void> setUnblock(bool value) async {
    unblock = value;
    await prefs.setBool('unblock', value);
    notifyListeners();
  }

  Future<void> setAmbient(bool value) async {
    ambient = value;
    await prefs.setBool('ambient', value);
    notifyListeners();
  }

  Future<void> setUsbExclusive(bool value) async {
    usbExclusive = value;
    await prefs.setBool('usbExclusive', value);
    notifyListeners();
  }

  Future<void> setAmbientIntensity(double value) async {
    ambientIntensity = value.clamp(.5, 1.5).toDouble();
    await prefs.setDouble('ambientIntensity', ambientIntensity);
    notifyListeners();
  }
}
