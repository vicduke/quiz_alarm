import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'question_service.dart';

/// Next time an alarm should fire, strictly after [now].
/// An empty [activeDays] means "ring once" (next occurrence of [time]).
/// Days use DateTime.weekday numbering: 1 = Monday ... 7 = Sunday.
DateTime calculateNextTrigger(
  TimeOfDay time,
  List<int> activeDays,
  DateTime now,
) {
  var candidate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  if (!candidate.isAfter(now)) {
    candidate = DateTime(
      now.year,
      now.month,
      now.day + 1,
      time.hour,
      time.minute,
    );
  }
  if (activeDays.isEmpty) return candidate;

  // Build each day from calendar fields (not +24h) so DST changes
  // can't shift the wall-clock time.
  while (!activeDays.contains(candidate.weekday)) {
    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day + 1,
      time.hour,
      time.minute,
    );
  }
  return candidate;
}

class AlarmProvider extends ChangeNotifier {
  List<AlarmItem> alarms = [];
  bool isAlarmRinging = false;

  final Completer<void> _loaded = Completer<void>();

  /// Completes once saved alarms have been read from storage.
  Future<void> get loaded => _loaded.future;

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
    _loadAlarms().then((_) => unawaited(refillQuestionBank()));
    _listenToRingStream();
  }

  /// Pre-generates questions for every enabled alarm's topics so nothing
  /// needs the network at ring time. Safe to call often; does nothing
  /// without an API key.
  Future<void> refillQuestionBank() async {
    try {
      await loaded;
      final topics = alarms
          .where((a) => a.isEnabled)
          .expand((a) => a.topics)
          .toSet();
      if (topics.isEmpty) return;
      final added = await QuestionService.prefetch(topics);
      if (added > 0) debugPrint('Question bank topped up with $added.');
    } catch (e) {
      debugPrint('Question prefetch failed: $e');
    }
  }

  void _listenToRingStream() {
    _ringSubscription = Alarm.ringStream.stream.listen((alarmSettings) async {
      if (isAlarmRinging) return;
      isAlarmRinging = true;

      // On a cold start the ring event can arrive before storage is read.
      // Wait, so we match the real alarm instead of the generic fallback.
      await loaded;

      final matched = alarms.firstWhere(
        (a) => a.id == alarmSettings.id,
        orElse: () => AlarmItem(
          id: alarmSettings.id,
          time: TimeOfDay.now(),
          topics: ['Pharmacology', 'General Knowledge'],
          label: alarmSettings.notificationTitle,
        ),
      );

      // A "ring once" alarm has now fired: turn it off so it can never
      // be rescheduled for tomorrow.
      if (matched.activeDays.isEmpty && matched.isEnabled) {
        matched.isEnabled = false;
        await saveAlarms();
      }

      if (_onAlarmTriggered != null) {
        _onAlarmTriggered!(matched);
      } else {
        _pendingRingingAlarm = matched;
      }
    });
  }

  AlarmSettings _buildSettings(
    AlarmItem alarm,
    DateTime when, {
    required String title,
    required String body,
  }) {
    return AlarmSettings(
      id: alarm.id,
      dateTime: when,
      assetAudioPath: alarm.audioPath,
      loopAudio: true,
      vibrate: alarm.vibrate,
      volume: alarm.volume,
      fadeDuration: alarm.fadeDuration,
      notificationTitle: title,
      notificationBody: body,
      enableNotificationOnKill: true,
      androidFullScreenIntent: true,
    );
  }

  Future<void> _scheduleNativeAlarm(AlarmItem alarm) async {
    if (!alarm.isEnabled) {
      await Alarm.stop(alarm.id);
      return;
    }

    final next = calculateNextTrigger(
      alarm.time,
      alarm.activeDays,
      DateTime.now(),
    );
    await Alarm.set(
      alarmSettings: _buildSettings(
        alarm,
        next,
        title: alarm.label.isEmpty ? 'Quiz Alarm' : alarm.label,
        body: 'Solve 2 questions (${alarm.topics.join(", ")}) to dismiss!',
      ),
    );
  }

  Future<void> addAlarm(AlarmItem alarm) async {
    alarms.add(alarm);
    await _scheduleNativeAlarm(alarm);
    await saveAlarms();
    unawaited(refillQuestionBank());
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
    unawaited(refillQuestionBank());
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
    unawaited(refillQuestionBank());
  }

  Future<void> snoozeAlarm(AlarmItem alarm, {int minutes = 5}) async {
    await Alarm.stop(alarm.id);
    isAlarmRinging = false;

    await Alarm.set(
      alarmSettings: _buildSettings(
        alarm,
        DateTime.now().add(Duration(minutes: minutes)),
        title: '${alarm.label} (Snoozed)',
        body: 'Mercy snooze ended! Answer 2 questions to dismiss.',
      ),
    );
  }

  Future<void> _loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_alarms');
      if (raw != null) {
        final loadedAlarms = <AlarmItem>[];
        try {
          for (final e in jsonDecode(raw) as List) {
            try {
              loadedAlarms.add(AlarmItem.fromJson(e as Map<String, dynamic>));
            } catch (err) {
              debugPrint('Skipping unreadable alarm: $err');
            }
          }
        } catch (err) {
          debugPrint('Saved alarms unreadable: $err');
        }
        alarms = loadedAlarms;

        // Re-register repeating alarms only. "Ring once" alarms are already
        // registered natively; rescheduling here would push a one that was
        // missed or already fired to tomorrow.
        for (final a in alarms) {
          if (a.isEnabled && a.activeDays.isNotEmpty) {
            await _scheduleNativeAlarm(a);
          }
        }
        notifyListeners();
      }
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
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
    _ringSubscription?.cancel();
    super.dispose();
  }
}
