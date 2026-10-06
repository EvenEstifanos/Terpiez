// settings_model.dart
//
// User preferences (currently the sound-effects toggle), persisted with
// SharedPreferences so they survive restarts.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsModel extends ChangeNotifier {
  static const String _soundKey = 'sound_enabled';

  bool _soundEnabled = true;

  bool get soundEnabled => _soundEnabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool(_soundKey) ?? true;
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
  }
}
