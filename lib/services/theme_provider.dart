/// App-wide display settings: dark / light theme and the 12 or 24 hour
/// clock. Saved on the device.
library;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;

  bool _use24Hour = false;

  /// True = 18:30, false = 6:30 PM.
  bool get use24Hour => _use24Hour;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkTheme') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _use24Hour = prefs.getBool('use24Hour') ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkTheme', isDark);
  }

  Future<void> setUse24Hour(bool value) async {
    _use24Hour = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use24Hour', value);
  }
}

/// Clock time in the chosen format: "18:30" or "6:30 PM".
String formatClock(DateTime t, {required bool use24Hour}) =>
    DateFormat(use24Hour ? 'HH:mm' : 'h:mm a').format(t);

/// [formatClock] for a time of day.
String formatTimeOfDay(TimeOfDay t, {required bool use24Hour}) =>
    formatClock(DateTime(2020, 1, 1, t.hour, t.minute), use24Hour: use24Hour);
