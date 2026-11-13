import 'package:material_ui/material_ui.dart';

class AlarmItem {
  final String id;
  TimeOfDay time;
  List<String> topics;
  bool isEnabled;
  List<int> activeDays; // 1 = Monday, 7 = Sunday
  String label; // e.g., "Morning Wakeup"

  AlarmItem({
    required this.id,
    required this.time,
    required this.topics,
    this.isEnabled = true,
    this.activeDays = const [1, 2, 3, 4, 5, 6, 7], // Default: Every day
    this.label = 'Quiz Alarm',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': time.hour,
    'minute': time.minute,
    'topics': topics,
    'isEnabled': isEnabled,
    'activeDays': activeDays,
    'label': label,
  };

  factory AlarmItem.fromJson(Map<String, dynamic> json) => AlarmItem(
    id: json['id'],
    time: TimeOfDay(hour: json['hour'], minute: json['minute']),
    topics: List<String>.from(json['topics'] ?? []),
    isEnabled: json['isEnabled'],
    activeDays: List<int>.from(json['activeDays'] ?? [1, 2, 3, 4, 5, 6, 7]),
    label: json['label'] ?? 'Quiz Alarm',
  );
}
