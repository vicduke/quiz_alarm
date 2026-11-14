/// Holds the list of alarms, keeps the system alarms in step with it and
/// tells the UI when one starts ringing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import 'alarm_backend.dart';
import 'question_service.dart';

/// Next time an alarm should fire, strictly after [now].
/// An empty [activeDays] means "ring once" (next occurrence of [time]).
/// Days use DateTime.weekday numbering: 1 = Monday ... 7 = Sunday.
DateTime calculateNextTrigger(
  TimeOfDay time,
  List<int> activeDays,
  DateTime now,
) {
  var candidate = DateTime(
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
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

/// "in 7 hours 5 minutes" style text for the gap between [now] and [next].
String describeTimeUntil(DateTime next, DateTime now) {
  final diff = next.difference(now);
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  if (diff.inMinutes < 1) return 'in less than a minute';
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  final parts = [
    if (days > 0) unit(days, 'day'),
    if (hours > 0) unit(hours, 'hour'),
    if (minutes > 0 && days == 0) unit(minutes, 'minute'),
  ];
  return 'in ${parts.join(' ')}';
}

class AlarmProvider extends ChangeNotifier {
  final AlarmBackend backend;

  List<AlarmItem> alarms = [];
  bool isAlarmRinging = false;

  final Completer<void> _loaded = Completer<void>();

  /// Completes once saved alarms have been read from storage.
  Future<void> get loaded => _loaded.future;

  /// Alarms that rang while another one was on screen, or before the UI
  /// was ready (app woken from a killed state).
  final List<AlarmItem> _waiting = [];
  Function(AlarmItem)? _onAlarmTriggered;
  StreamSubscription<AlarmRing>? _ringSubscription;

  set onAlarmTriggered(Function(AlarmItem)? callback) {
    _onAlarmTriggered = callback;
    _showNextWaiting();
  }

  AlarmProvider({AlarmBackend? backend})
    : backend = backend ?? AlarmBackend.forPlatform() {
    _loadAlarms().then((_) => unawaited(refillQuestionBank()));
    _ringSubscription = this.backend.rings.listen(_onRing);
  }

  /// Asks the AI for fresh questions on the alarms' topics when they are
  /// running low, so nothing needs the network at ring time. Safe to call
  /// often; does nothing without an API key.
  Future<void> refillQuestionBank() async {
    try {
      await loaded;
      if (alarms.isEmpty) return;
      // An alarm with no topics means "any topic".
      final selectors = alarms.any((a) => a.topics.isEmpty)
          ? const <String>[]
          : alarms.expand((a) => a.topics).toSet().toList();
      final result = await QuestionService.topUp(selectors);
      if (result.error != null) {
        debugPrint('Question top-up failed: ${result.error}');
      }
    } catch (e) {
      debugPrint('Question top-up failed: $e');
    }
  }

  Future<void> _onRing(AlarmRing ring) async {
    // On a cold start the ring event can arrive before storage is read.
    // Wait, so we match the real alarm instead of the generic fallback.
    await loaded;

    final matched = alarms.firstWhere(
      (a) => a.id == ring.id,
      orElse: () => AlarmItem(
        id: ring.id,
        time: TimeOfDay.now(),
        topics: const [],
        activeDays: const [],
        label: ring.title,
      ),
    );

    // A "ring once" alarm has now fired: turn it off so it can never
    // be rescheduled for tomorrow.
    if (matched.activeDays.isEmpty && matched.isEnabled) {
      matched.isEnabled = false;
      await saveAlarms();
    }

    if (!_waiting.any((a) => a.id == matched.id)) _waiting.add(matched);
    _showNextWaiting();
  }

  void _showNextWaiting() {
    if (isAlarmRinging || _waiting.isEmpty || _onAlarmTriggered == null) return;
    isAlarmRinging = true;
    _onAlarmTriggered!(_waiting.removeAt(0));
  }

  /// The ring screen calls this when it closes. Shows the next alarm if
  /// another one started ringing meanwhile.
  void ringScreenClosed() {
    isAlarmRinging = false;
    _showNextWaiting();
  }

  Future<AlarmRequest> _request(
    AlarmItem alarm,
    DateTime when, {
    String? title,
    String? body,
  }) async {
    final name = alarm.label.isEmpty ? 'Quiz Alarm' : alarm.label;
    var topics = 'your topics';
    try {
      topics = await QuestionRepository.describeSelection(alarm.topics);
    } catch (_) {}
    return AlarmRequest(
      id: alarm.id,
      dateTime: when,
      audioPath: alarm.audioPath,
      vibrate: alarm.vibrate,
      // Always the loudest the phone can go, whatever its volume is set to.
      volume: 1.0,
      fadeDuration: alarm.fadeDuration,
      title: title ?? name,
      body:
          body ??
          'Answer ${alarm.requiredStreak} in a row ($topics) to dismiss!',
    );
  }

  Future<void> _scheduleNativeAlarm(AlarmItem alarm) async {
    if (!alarm.isEnabled) {
      await backend.stop(alarm.id);
      return;
    }
    final next = calculateNextTrigger(
      alarm.time,
      alarm.activeDays,
      DateTime.now(),
    );
    await backend.set(await _request(alarm, next));
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
    await backend.stop(id);
    await saveAlarms();
  }

  Future<void> dismissAlarm(AlarmItem alarm) async {
    await backend.stop(alarm.id);
    // Automatically schedule next occurrence if repeating days are active
    if (alarm.isEnabled && alarm.activeDays.isNotEmpty) {
      await _scheduleNativeAlarm(alarm);
    } else {
      alarm.isEnabled = false;
      await saveAlarms();
    }
    unawaited(refillQuestionBank());
  }

  /// Silences [alarm] and rings it again after its own snooze length.
  Future<void> snoozeAlarm(AlarmItem alarm) async {
    await backend.set(
      await _request(
        alarm,
        DateTime.now().add(Duration(minutes: alarm.snoozeMinutes)),
        title: '${alarm.label} (Snoozed)',
        body:
            'Snooze ended! Answer ${alarm.requiredStreak} in a row to dismiss.',
      ),
    );
  }

  /// Makes [alarm] ring [after] from now without changing its schedule
  /// permanently (used by the simulator's "Ring now" button).
  Future<void> ringSoon(
    AlarmItem alarm, {
    Duration after = const Duration(seconds: 3),
  }) async {
    await backend.set(await _request(alarm, DateTime.now().add(after)));
  }

  Future<void> _loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_alarms');
      if (raw == null) return;

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

      var changed = false;
      final now = DateTime.now();
      for (final a in alarms.where((a) => a.isEnabled)) {
        try {
          // Registering an alarm again silences it if it is ringing and
          // wipes a pending snooze, so leave those two cases alone.
          if (await backend.isRinging(a.id)) continue;
          final registered = backend.scheduledTime(a.id);
          if (registered != null && registered.isAfter(now)) continue;

          if (a.activeDays.isEmpty) {
            // A "ring once" alarm that is no longer registered has fired
            // or was missed. Rescheduling would push it to tomorrow.
            a.isEnabled = false;
            changed = true;
          } else {
            await _scheduleNativeAlarm(a);
          }
        } catch (err) {
          debugPrint('Could not restore alarm ${a.id}: $err');
        }
      }
      if (changed) {
        await saveAlarms();
      } else {
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
