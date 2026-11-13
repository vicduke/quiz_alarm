/// Data classes shared across the app: study units, topics, questions
/// and alarms.
library;

import 'dart:convert';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

enum QuestionType { mcq, saq }

/// A course unit, e.g. "Pharmacology". Holds several [Topic]s.
class StudyUnit {
  final String id;
  final String name;
  final String description;

  const StudyUnit({
    required this.id,
    required this.name,
    this.description = '',
  });
}

/// A subtopic inside a unit, e.g. "Antimicrobials".
class Topic {
  final String id;
  final String unitId;
  final String name;
  final bool isCustom;

  const Topic({
    required this.id,
    required this.unitId,
    required this.name,
    this.isCustom = false,
  });
}

/// How the user is doing on one topic.
class TopicStats {
  /// Questions stored for the topic.
  final int total;

  /// Questions answered at least once.
  final int seen;

  /// Questions whose most recent answer was correct.
  final int mastered;

  const TopicStats({this.total = 0, this.seen = 0, this.mastered = 0});

  int get unseen => total - seen;
}

class Question {
  final String id;

  /// Id of the [Topic] this question belongs to.
  final String topicId;

  /// Topic name, kept on the question so screens can show it directly.
  final String topic;
  final QuestionType type;
  final String questionText;
  final List<String> options;
  final String correctAnswer;

  /// Other spellings / names that also count as correct for typed answers
  /// (e.g. "Epinephrine" for "Adrenaline").
  final List<String> altAnswers;

  /// Why the answer is right. Stored so explanations work offline.
  final String explanation;

  /// Where the question came from: 'seed', 'ai' or 'user'.
  final String source;

  const Question({
    required this.id,
    this.topicId = '',
    required this.topic,
    required this.type,
    required this.questionText,
    this.options = const [],
    required this.correctAnswer,
    this.altAnswers = const [],
    this.explanation = '',
    this.source = 'seed',
  });

  /// The same question with its options in a new random order, so the
  /// right answer is not always in the same place.
  Question shuffled([Random? rng]) =>
      copyWith(options: List<String>.of(options)..shuffle(rng ?? Random()));

  Question copyWith({String? explanation, List<String>? options}) => Question(
    id: id,
    topicId: topicId,
    topic: topic,
    type: type,
    questionText: questionText,
    options: options ?? this.options,
    correctAnswer: correctAnswer,
    altAnswers: altAnswers,
    explanation: explanation ?? this.explanation,
    source: source,
  );

  /// Reads a row of the `questions` table joined with its topic name.
  factory Question.fromRow(Map<String, Object?> row) {
    List<String> list(Object? raw) {
      try {
        return List<String>.from(jsonDecode(raw as String) as List);
      } catch (_) {
        return const [];
      }
    }

    return Question(
      id: row['id'] as String,
      topicId: row['topic_id'] as String,
      topic: (row['topic_name'] ?? '') as String,
      type: row['type'] == 'mcq' ? QuestionType.mcq : QuestionType.saq,
      questionText: row['text'] as String,
      options: list(row['options']),
      correctAnswer: row['answer'] as String,
      altAnswers: list(row['alt_answers']),
      explanation: (row['explanation'] ?? '') as String,
      source: (row['source'] ?? 'seed') as String,
    );
  }
}

class AlarmItem {
  final int id; // 32-bit integer required by native Android AlarmManager
  TimeOfDay time;

  /// Topic or unit ids to draw questions from. Empty means "any topic".
  /// (Alarms saved by older versions hold topic names; those still resolve.)
  List<String> topics;
  bool isEnabled;
  List<int> activeDays; // 1 = Mon, 7 = Sun. Empty = ring once.
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

  /// A random id that is not in [taken].
  static int generateSafeId([Iterable<int> taken = const []]) {
    final used = taken.toSet();
    final rng = Random();
    while (true) {
      final id = rng.nextInt(900000) + 100000;
      if (!used.contains(id)) return id;
    }
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
