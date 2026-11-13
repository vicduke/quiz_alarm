import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_alarm/models/models.dart';
import 'package:quiz_alarm/services/alarm_backend.dart';
import 'package:quiz_alarm/services/alarm_provider.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

/// Records what the provider asks the system to do.
class FakeBackend implements AlarmBackend {
  final Map<int, DateTime> registered = {};
  final Set<int> ringing = {};
  final List<int> setCalls = [];
  final List<int> stopCalls = [];
  final StreamController<AlarmRing> controller = StreamController<AlarmRing>();

  @override
  bool get isSimulated => true;
  @override
  Future<void> init() async {}
  @override
  Stream<AlarmRing> get rings => controller.stream;
  @override
  Future<void> set(AlarmRequest request) async {
    setCalls.add(request.id);
    ringing.remove(request.id);
    registered[request.id] = request.dateTime;
  }

  @override
  Future<void> stop(int id) async {
    stopCalls.add(id);
    ringing.remove(id);
    registered.remove(id);
  }

  @override
  Future<bool> isRinging(int id) async => ringing.contains(id);
  @override
  DateTime? scheduledTime(int id) => registered[id];
}

AlarmItem alarm(int id, {List<int> days = const [1, 2, 3, 4, 5, 6, 7]}) =>
    AlarmItem(
      id: id,
      time: const TimeOfDay(hour: 7, minute: 0),
      topics: const [],
      activeDays: days,
    );

Map<String, Object> saved(List<AlarmItem> alarms) => {
  'saved_alarms': jsonEncode(alarms.map((a) => a.toJson()).toList()),
};

void main() {
  test(
    'opening the app never re-registers a ringing or snoozed alarm',
    () async {
      await resetApp(prefs: saved([alarm(1), alarm(2), alarm(3)]));
      final backend = FakeBackend()
        ..ringing.add(1) // ringing right now
        ..registered[1] = DateTime.now().subtract(const Duration(seconds: 30))
        ..registered[2] = DateTime.now().add(
          const Duration(minutes: 4),
        ); // snooze
      final provider = AlarmProvider(backend: backend);
      await provider.loaded;

      expect(backend.setCalls, [3]); // only the one that was not registered
      expect(backend.ringing, contains(1));
    },
  );

  test(
    'a ring-once alarm that is no longer registered is switched off',
    () async {
      await resetApp(prefs: saved([alarm(1, days: const [])]));
      final backend = FakeBackend();
      final provider = AlarmProvider(backend: backend);
      await provider.loaded;

      expect(backend.setCalls, isEmpty);
      expect(provider.alarms.single.isEnabled, isFalse);
    },
  );

  test('rings reach the UI one at a time, even before it is ready', () async {
    await resetApp(prefs: saved([alarm(1), alarm(2, days: const [])]));
    final backend = FakeBackend()
      ..registered[2] = DateTime.now().add(const Duration(hours: 1));
    final provider = AlarmProvider(backend: backend);
    await provider.loaded;

    backend.controller.add(const AlarmRing(1, 'one'));
    backend.controller.add(const AlarmRing(2, 'two'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final shown = <int>[];
    provider.onAlarmTriggered = (a) => shown.add(a.id);
    expect(shown, [1]);
    expect(provider.isAlarmRinging, isTrue);

    provider.ringScreenClosed();
    expect(shown, [1, 2]);
    // The ring-once alarm switched itself off when it fired.
    expect(provider.alarms.firstWhere((a) => a.id == 2).isEnabled, isFalse);
  });

  test(
    'dismiss reschedules a repeating alarm; snooze keeps the same id',
    () async {
      await resetApp();
      final backend = FakeBackend();
      final provider = AlarmProvider(backend: backend);
      await provider.loaded;
      final a = alarm(7);
      await provider.addAlarm(a);

      a.snoozeMinutes = 10;
      await provider.snoozeAlarm(a);
      final snoozeAt = backend.registered[7]!;
      expect(
        snoozeAt.difference(DateTime.now()).inMinutes,
        inInclusiveRange(9, 10),
      );

      await provider.dismissAlarm(a);
      expect(backend.registered[7]!.isAfter(snoozeAt), isTrue);
      expect(a.isEnabled, isTrue);
    },
  );

  test('simulated backend rings, reports and stops', () async {
    await resetApp();
    final backend = SimulatedAlarmBackend(playSound: false);
    await backend.init();
    final rings = <int>[];
    final sub = backend.rings.listen((r) => rings.add(r.id));

    await backend.set(
      AlarmRequest(
        id: 5,
        dateTime: DateTime.now().add(const Duration(milliseconds: 30)),
        audioPath: 'assets/sounds/alarm.mp3',
        title: 't',
        body: 'b',
      ),
    );
    expect(backend.scheduledTime(5), isNotNull);
    expect(await backend.isRinging(5), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(rings, [5]);
    expect(await backend.isRinging(5), isTrue);

    await backend.stop(5);
    expect(await backend.isRinging(5), isFalse);
    expect(backend.scheduledTime(5), isNull);
    await sub.cancel();
  });

  test('difficulty and snooze length are saved; old alarms get defaults', () {
    final a = alarm(1)
      ..requiredStreak = 9
      ..snoozeMinutes = 3;
    final back = AlarmItem.fromJson(a.toJson());
    expect(back.requiredStreak, 9);
    expect(back.snoozeMinutes, 3);

    final old = a.toJson()
      ..remove('requiredStreak')
      ..remove('snoozeMinutes');
    expect(AlarmItem.fromJson(old).requiredStreak, 2);
    expect(AlarmItem.fromJson(old).snoozeMinutes, 5);

    // Out-of-range values from a bad file are pulled back into range.
    final bad = a.toJson()
      ..['requiredStreak'] = 99
      ..['snoozeMinutes'] = 7;
    expect(AlarmItem.fromJson(bad).requiredStreak, 15);
    expect(AlarmItem.fromJson(bad).snoozeMinutes, 5);

    expect(AlarmItem.difficultyName(2), 'Easy');
    expect(AlarmItem.difficultyName(3), 'Medium');
    expect(AlarmItem.difficultyName(5), 'Hard');
    expect(AlarmItem.difficultyName(12), 'Custom');
  });
}
