/// The thing that actually rings.
///
/// [NativeAlarmBackend] uses the `alarm` plugin (Android / iOS).
/// [SimulatedAlarmBackend] uses in-app timers and is used where the plugin
/// does not exist: the web "mini emulator", desktop and tests. It keeps its
/// schedule in SharedPreferences so it survives a reload like the real one.
library;

import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One alarm to register with the system.
class AlarmRequest {
  final int id;
  final DateTime dateTime;
  final String audioPath;
  final bool vibrate;
  final double volume;
  final double fadeDuration;
  final String title;
  final String body;

  const AlarmRequest({
    required this.id,
    required this.dateTime,
    required this.audioPath,
    required this.title,
    required this.body,
    this.vibrate = true,
    this.volume = 1.0,
    this.fadeDuration = 0,
  });
}

/// "Alarm [id] started ringing."
class AlarmRing {
  final int id;
  final String title;
  const AlarmRing(this.id, this.title);
}

abstract class AlarmBackend {
  /// True when alarms are simulated inside the app (no OS alarm).
  bool get isSimulated;

  Future<void> init();

  /// Fires when an alarm starts ringing, including one that was already
  /// ringing when the app was opened.
  Stream<AlarmRing> get rings;

  /// Registers [request], replacing (and silencing) any alarm with its id.
  Future<void> set(AlarmRequest request);

  /// Cancels alarm [id] and silences it if it is ringing.
  Future<void> stop(int id);

  Future<bool> isRinging(int id);

  /// When alarm [id] is registered to ring, or null if it is not registered.
  DateTime? scheduledTime(int id);

  /// The right backend for the device the app is running on.
  static AlarmBackend forPlatform() {
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return mobile ? NativeAlarmBackend() : SimulatedAlarmBackend();
  }
}

class NativeAlarmBackend implements AlarmBackend {
  @override
  bool get isSimulated => false;

  @override
  Future<void> init() => Alarm.init();

  @override
  late final Stream<AlarmRing> rings = Alarm.ringStream.stream.map(
    (s) => AlarmRing(s.id, s.notificationTitle),
  );

  @override
  Future<void> set(AlarmRequest r) async {
    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: r.id,
        dateTime: r.dateTime,
        assetAudioPath: r.audioPath,
        loopAudio: true,
        vibrate: r.vibrate,
        volume: r.volume,
        fadeDuration: r.fadeDuration,
        notificationTitle: r.title,
        notificationBody: r.body,
        enableNotificationOnKill: true,
        androidFullScreenIntent: true,
      ),
    );
  }

  @override
  Future<void> stop(int id) async {
    await Alarm.stop(id);
  }

  @override
  Future<bool> isRinging(int id) => Alarm.isRinging(id);

  @override
  DateTime? scheduledTime(int id) {
    for (final a in Alarm.getAlarms()) {
      if (a.id == id) return a.dateTime;
    }
    return null;
  }
}

class SimulatedAlarmBackend implements AlarmBackend {
  static const String _prefKey = 'simulated_alarms';

  /// Set to false in tests so no audio plugin is touched.
  final bool playSound;

  SimulatedAlarmBackend({this.playSound = true});

  final StreamController<AlarmRing> _rings =
      StreamController<AlarmRing>.broadcast();
  final Map<int, AlarmRequest> _scheduled = {};
  final Map<int, Timer> _timers = {};
  final Set<int> _ringing = {};
  final List<AlarmRing> _backlog = [];
  AudioPlayer? _player;

  @override
  bool get isSimulated => true;

  @override
  Stream<AlarmRing> get rings async* {
    // Hand over rings that happened before anyone listened.
    while (_backlog.isNotEmpty) {
      yield _backlog.removeAt(0);
    }
    yield* _rings.stream;
  }

  @override
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null) return;
      final now = DateTime.now();
      for (final e in jsonDecode(raw) as List) {
        final r = AlarmRequest(
          id: e['id'] as int,
          dateTime: DateTime.fromMillisecondsSinceEpoch(e['at'] as int),
          audioPath: e['audio'] as String,
          title: e['title'] as String,
          body: e['body'] as String,
        );
        // A real alarm keeps ringing while the app is closed, so one
        // whose time has passed is treated as still ringing; future ones
        // are re-armed.
        if (r.dateTime.isAfter(now)) {
          _arm(r);
        } else {
          _scheduled[r.id] = r;
          _fire(r);
        }
      }
    } catch (e) {
      debugPrint('Simulated alarms could not be restored: $e');
    }
  }

  void _arm(AlarmRequest r) {
    _scheduled[r.id] = r;
    _timers[r.id]?.cancel();
    final wait = r.dateTime.difference(DateTime.now());
    _timers[r.id] = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => _fire(r),
    );
  }

  void _fire(AlarmRequest r) {
    _ringing.add(r.id);
    final ring = AlarmRing(r.id, r.title);
    if (_rings.hasListener) {
      _rings.add(ring);
    } else {
      _backlog.add(ring);
    }
    if (playSound) unawaited(_startSound(r));
  }

  Future<void> _startSound(AlarmRequest r) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      final path = r.audioPath;
      await player.play(
        path.startsWith('assets/')
            ? AssetSource(path.substring('assets/'.length))
            : DeviceFileSource(path),
        volume: r.volume,
      );
    } catch (e) {
      debugPrint('Simulated alarm sound failed: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode([
        for (final r in _scheduled.values)
          {
            'id': r.id,
            'at': r.dateTime.millisecondsSinceEpoch,
            'audio': r.audioPath,
            'title': r.title,
            'body': r.body,
          },
      ]),
    );
  }

  @override
  Future<void> set(AlarmRequest request) async {
    await stop(request.id);
    _arm(request);
    await _save();
  }

  @override
  Future<void> stop(int id) async {
    _timers.remove(id)?.cancel();
    _scheduled.remove(id);
    final wasRinging = _ringing.remove(id);
    if (wasRinging && _ringing.isEmpty) {
      try {
        await _player?.stop();
      } catch (_) {}
    }
    await _save();
  }

  @override
  Future<bool> isRinging(int id) async => _ringing.contains(id);

  @override
  DateTime? scheduledTime(int id) => _scheduled[id]?.dateTime;
}
