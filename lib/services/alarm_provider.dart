import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class AlarmProvider extends ChangeNotifier {
  List<AlarmItem> alarms = [];
  Timer? _clockTimer;
  DateTime now = DateTime.now();
  bool isAlarmRinging = false;

  AlarmItem? _pendingRingingAlarm;
  Function(AlarmItem)? _onAlarmTriggered;
  StreamSubscription<AlarmSettings>? _ringSubscription;

  set onAlarmTriggered(Function(AlarmItem)? callback) {
    _onAlarmTriggered = callback;
    // Flush if an alarm woke the app from a killed state before UI mounted
    if (_pendingRingingAlarm != null && callback != null) {
      final alarm = _pendingRingingAlarm!;
      _pendingRingingAlarm = null;
      callback(alarm);
    }
  }

  AlarmProvider() {
    _loadAlarms();
    _startDisplayClock();
    _listenToRingStream();
  }

  void _startDisplayClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      now = DateTime.now();
      notifyListeners();
    });
  }

  void _listenToRingStream() {
    _ringSubscription = Alarm.ringStream.stream.listen((alarmSettings) {
      if (isAlarmRinging) return;
      isAlarmRinging = true;

      final matched = alarms.firstWhere(
        (a) => a.id == alarmSettings.id,
        orElse: () => AlarmItem(
          id: alarmSettings.id,
          time: TimeOfDay.now(),
          topics: ['Pharmacology', 'General Knowledge'],
          label: alarmSettings.notificationTitle,
        ),
      );

      if (_onAlarmTriggered != null) {
        _onAlarmTriggered!(matched);
      } else {
        _pendingRingingAlarm = matched;
      }
    });
  }

  DateTime _calculateNextTrigger(AlarmItem alarm) {
    final current = DateTime.now();
    DateTime candidate = DateTime(
      current.year,
      current.month,
      current.day,
      alarm.time.hour,
      alarm.time.minute,
    );

    if (!candidate.isAfter(current)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    if (alarm.activeDays.isEmpty) return candidate;

    while (!alarm.activeDays.contains(candidate.weekday)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<void> _scheduleNativeAlarm(AlarmItem alarm) async {
    if (!alarm.isEnabled) {
      await Alarm.stop(alarm.id);
      return;
    }

    final nextDateTime = _calculateNextTrigger(alarm);
    final settings = AlarmSettings(
      id: alarm.id,
      dateTime: nextDateTime,
      assetAudioPath: alarm.audioPath,
      loopAudio: true,
      vibrate: alarm.vibrate,
      volume: alarm.volume,
      fadeDuration: alarm.fadeDuration,
      notificationTitle: alarm.label.isEmpty ? 'Quiz Alarm' : alarm.label,
      notificationBody:
          'Solve 2 questions (${alarm.topics.join(", ")}) to dismiss!',
      enableNotificationOnKill: true,
      androidFullScreenIntent: true,
    );

    await Alarm.set(alarmSettings: settings);
  }

  Future<void> addAlarm(AlarmItem alarm) async {
    alarms.add(alarm);
    await _scheduleNativeAlarm(alarm);
    await saveAlarms();
  }

  Future<void> updateAlarm(AlarmItem alarm) async {
    final index = alarms.indexWhere((a) => a.id == alarm.id);
    if (index != -1) {
      alarms[index] = alarm;
    } else {
      alarms.add(alarm);
    }
    await _scheduleNativeAlarm(alarm);
    await saveAlarms();
  }

  Future<void> deleteAlarm(int id) async {
    alarms.removeWhere((a) => a.id == id);
    await Alarm.stop(id);
    await saveAlarms();
  }

  Future<void> dismissAlarm(AlarmItem alarm) async {
    await Alarm.stop(alarm.id);
    isAlarmRinging = false;
    // Automatically schedule next occurrence if repeating days are active
    if (alarm.isEnabled && alarm.activeDays.isNotEmpty) {
      await _scheduleNativeAlarm(alarm);
    } else {
      alarm.isEnabled = false;
      await saveAlarms();
    }
  }

  Future<void> snoozeAlarm(AlarmItem alarm, {int minutes = 5}) async {
    await Alarm.stop(alarm.id);
    isAlarmRinging = false;

    final snoozeTime = DateTime.now().add(Duration(minutes: minutes));
    final snoozeSettings = AlarmSettings(
      id: alarm.id,
      dateTime: snoozeTime,
      assetAudioPath: alarm.audioPath,
      loopAudio: true,
      vibrate: alarm.vibrate,
      volume: alarm.volume,
      fadeDuration: alarm.fadeDuration,
      notificationTitle: '${alarm.label} (Snoozed)',
      notificationBody: 'Mercy snooze ended! Answer 2 questions to dismiss.',
      enableNotificationOnKill: true,
      androidFullScreenIntent: true,
    );

    await Alarm.set(alarmSettings: snoozeSettings);
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('saved_alarms');
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      alarms = decoded.map((e) => AlarmItem.fromJson(e)).toList();
      for (final a in alarms) {
        if (a.isEnabled) {
          await _scheduleNativeAlarm(a);
        }
      }
      notifyListeners();
    }
  }

  Future<void> saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_alarms',
      jsonEncode(alarms.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _ringSubscription?.cancel();
    super.dispose();
  }
}
