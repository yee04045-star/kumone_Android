import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppIconChoice {
  red('红');

  final String label;
  const AppIconChoice(this.label);
  String get asset => 'assets/icons/$name.png';
}

// Android owns the one persisted selection, shared by launcher and splash.
class AppIconStore extends ChangeNotifier {
  static const channel = MethodChannel('im.kumone/app_icon');
  AppIconChoice selected = AppIconChoice.red;
  bool busy = false;
  List<AppIconChoice> get visibleChoices => List.unmodifiable(AppIconChoice.values);

  Future<void> load() async {
    try {
      final name = await channel.invokeMethod<String>('getIcon');
      selected = AppIconChoice.values
          .firstWhere((e) => e.name == name, orElse: () => AppIconChoice.red);
      notifyListeners();
    } on MissingPluginException {
      // Non-Android previews retain the default.
    }
  }

  Future<void> select(AppIconChoice choice) async {
    if (busy || selected == choice) return;
    busy = true;
    notifyListeners();
    try {
      await channel.invokeMethod<void>('setIcon', {'icon': choice.name});
      selected = choice;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
