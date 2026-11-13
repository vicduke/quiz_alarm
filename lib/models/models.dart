import 'package:material_ui/material_ui.dart';

import 'dart:math';

enum QuestionType { mcq, saq }

class Question {
  final String id;
  final String topic;
  final QuestionType type;
  final String questionText;
  final List<String> options;
  final String correctAnswer;

  Question({
    required this.id,
    required this.topic,
    required this.type,
    required this.questionText,
    this.options = const [],
    required this.correctAnswer,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'topic': topic,
    'type': type == QuestionType.mcq ? 'mcq' : 'saq',
    'questionText': questionText,
    'options': options,
    'correctAnswer': correctAnswer,
  };

  factory Question.fromJson(Map<String, dynamic> json) => Question(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    topic: json['topic'] ?? 'General',
    type: json['type'] == 'mcq' ? QuestionType.mcq : QuestionType.saq,
    questionText: json['questionText'],
    options: List<String>.from(json['options'] ?? []),
    correctAnswer: json['correctAnswer'],
  );
}

class AlarmItem {
  final int id; // 32-bit integer required by native Android AlarmManager
  TimeOfDay time;
  List<String> topics;
  bool isEnabled;
  List<int> activeDays; // 1 = Mon, 7 = Sun
  String label;
  String audioPath; // Asset path or local storage file path
  bool vibrate;
  double fadeDuration; // Seconds for gradual volume fade-in
  double volume; // 0.0 to 1.0 enforced volume

  AlarmItem({
    required this.id,
    required this.time,
    required this.topics,
    this.isEnabled = true,
    this.activeDays = const [1, 2, 3, 4, 5, 6, 7],
    this.label = 'Quiz Alarm',
    this.audioPath = 'assets/sounds/alarm.mp3',
    this.vibrate = true,
    this.fadeDuration = 5.0,
    this.volume = 1.0,
  });

  static int generateSafeId() => Random().nextInt(900000) + 100000;

  AlarmItem copyWith({
    int? id,
    TimeOfDay? time,
    List<String>? topics,
    bool? isEnabled,
    List<int>? activeDays,
    String? label,
    String? audioPath,
    bool? vibrate,
    double? fadeDuration,
    double? volume,
  }) {
    return AlarmItem(
      id: id ?? this.id,
      time: time ?? this.time,
      topics: topics ?? this.topics,
      isEnabled: isEnabled ?? this.isEnabled,
      activeDays: activeDays ?? this.activeDays,
      label: label ?? this.label,
      audioPath: audioPath ?? this.audioPath,
      vibrate: vibrate ?? this.vibrate,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': time.hour,
    'minute': time.minute,
    'topics': topics,
    'isEnabled': isEnabled,
    'activeDays': activeDays,
    'label': label,
    'audioPath': audioPath,
    'vibrate': vibrate,
    'fadeDuration': fadeDuration,
    'volume': volume,
  };

  factory AlarmItem.fromJson(Map<String, dynamic> json) => AlarmItem(
    id: json['id'] is int
        ? json['id']
        : int.tryParse(json['id'].toString()) ?? generateSafeId(),
    time: TimeOfDay(hour: json['hour'], minute: json['minute']),
    topics: List<String>.from(json['topics'] ?? []),
    isEnabled: json['isEnabled'] ?? true,
    activeDays: List<int>.from(json['activeDays'] ?? [1, 2, 3, 4, 5, 6, 7]),
    label: json['label'] ?? 'Quiz Alarm',
    audioPath: json['audioPath'] ?? 'assets/sounds/alarm.mp3',
    vibrate: json['vibrate'] ?? true,
    fadeDuration: (json['fadeDuration'] ?? 5.0).toDouble(),
    volume: (json['volume'] ?? 1.0).toDouble(),
  );
}
