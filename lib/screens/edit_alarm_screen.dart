/// Add / edit one alarm: time, repeat days, name, topics, ringtone, fade.
library;

import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/alarm_provider.dart';
import '../services/bank_provider.dart';
import '../widgets/topic_picker.dart';

class EditAlarmScreen extends StatefulWidget {
  final AlarmItem? existingAlarm;

  const EditAlarmScreen({super.key, this.existingAlarm});

  @override
  State<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends State<EditAlarmScreen> {
  // Preset ringtones (bundled in assets/sounds).
  static const List<Map<String, String>> _defaultRingtones = [
    {'name': 'Default Alarm', 'path': 'assets/sounds/alarm.mp3'},
    {'name': 'Correct Chime', 'path': 'assets/sounds/correct.mp3'},
    {'name': 'Wrong Buzzer', 'path': 'assets/sounds/wrong.mp3'},
  ];
  static const List<double> _fadeOptions = [0.0, 5.0, 10.0, 30.0, 60.0];

  late TimeOfDay _selectedTime;
  late final TextEditingController _labelCtrl;
  late List<String> _topics; // topic/unit ids; empty = all topics
  late String _audioPath;
  late String _audioName;
  late bool _vibrate;
  late double _fadeDuration;

  int _repeatMode = 0; // 0 = Ring once, 1 = Custom
  List<int> _customDays = []; // 1=Mon, 7=Sun

  @override
  void initState() {
    super.initState();
    final a = widget.existingAlarm;
    _selectedTime = a != null ? a.time : TimeOfDay.now();
    _labelCtrl = TextEditingController(text: a?.label ?? 'Quiz Alarm');
    _topics = List.of(a?.topics ?? const []);
    _audioPath = a?.audioPath ?? 'assets/sounds/alarm.mp3';
    _audioName = _nameOf(_audioPath);
    _vibrate = a?.vibrate ?? true;
    _fadeDuration = a?.fadeDuration ?? 5.0;

    if (a != null && a.activeDays.isNotEmpty) {
      _repeatMode = 1;
      _customDays = List.from(a.activeDays);
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  String _nameOf(String path) {
    for (final tone in _defaultRingtones) {
      if (tone['path'] == path) return tone['name']!;
    }
    // Saved custom files are named "<timestamp>_<original name>".
    return path.split('/').last.replaceFirst(RegExp(r'^\d+_'), '');
  }

  List<int> get _activeDays => _repeatMode == 1 ? _customDays : const [];

  String _getTimeUntil() {
    final now = DateTime.now();
    final next = calculateNextTrigger(_selectedTime, _activeDays, now);
    return 'Next alarm ${describeTimeUntil(next, now)}';
  }

  void _saveAlarm() {
    final provider = Provider.of<AlarmProvider>(context, listen: false);
    final label = _labelCtrl.text.trim();
    final newAlarm = AlarmItem(
      id:
          widget.existingAlarm?.id ??
          AlarmItem.generateSafeId(provider.alarms.map((a) => a.id)),
      time: _selectedTime,
      topics: _topics,
      label: label.isEmpty ? 'Quiz Alarm' : label,
      audioPath: _audioPath,
      vibrate: _vibrate,
      activeDays: List.of(_activeDays),
      fadeDuration: _fadeDuration,
      volume: widget.existingAlarm?.volume ?? 1.0,
    );

    if (widget.existingAlarm == null) {
      provider.addAlarm(newAlarm);
    } else {
      provider.updateAlarm(newAlarm);
    }
    Navigator.pop(context);
  }

  Future<void> _pickTopics() async {
    final bank = context.read<BankProvider>();
    final picked = await showTopicPickerSheet(
      context,
      initial: bank.selectedIds(_topics),
      title: 'Topics for this alarm',
    );
    if (picked == null || !mounted) return;
    // Every topic ticked is the same as "all topics", which also covers
    // topics added later.
    final all = picked.length == bank.topics.length;
    setState(() => _topics = all ? [] : picked.toList());
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;
    // file_picker hands back a temporary cache copy the OS may delete.
    // Keep our own copy so the alarm never goes silent.
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/ringtones');
      await dir.create(recursive: true);
      final name = result.files.single.name;
      final dest = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
      await File(result.files.single.path!).copy(dest);
      if (!mounted) return;
      setState(() {
        _audioPath = dest;
        _audioName = name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that audio file.')),
      );
    }
  }

  void _showRingtonePicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Ringtone',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final tone in _defaultRingtones)
                ListTile(
                  title: Text(tone['name']!),
                  trailing: _audioPath == tone['path']
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() {
                      _audioPath = tone['path']!;
                      _audioName = tone['name']!;
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
              // Copying a picked file needs real file storage.
              if (!kIsWeb) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Pick from device...'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAudioFile();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showFadePicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Fade-in Duration',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final duration in _fadeOptions)
                ListTile(
                  title: Text(
                    duration == 0 ? 'None' : '${duration.toInt()} seconds',
                  ),
                  trailing: _fadeDuration == duration
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() => _fadeDuration = duration);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cardColor = scheme.surfaceContainerHighest;
    final bank = context.watch<BankProvider>();
    final muted = TextStyle(color: scheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
        ),
        leadingWidth: 88,
        title: Text(
          widget.existingAlarm == null ? 'Add alarm' : 'Edit alarm',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveAlarm,
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Center(child: Text(_getTimeUntil(), style: muted)),
          const SizedBox(height: 16),

          // Time Picker (Cupertino Style)
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: theme.brightness,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                  ),
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: DateTime(
                  2020,
                  1,
                  1,
                  _selectedTime.hour,
                  _selectedTime.minute,
                ),
                onDateTimeChanged: (dt) =>
                    setState(() => _selectedTime = TimeOfDay.fromDateTime(dt)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Ring once')),
              ButtonSegment(value: 1, label: Text('Repeat')),
            ],
            selected: {_repeatMode},
            onSelectionChanged: (s) => setState(() => _repeatMode = s.first),
          ),
          const SizedBox(height: 16),

          if (_repeatMode == 1) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getCustomDaysText(),
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildDayBubble('S', 7, scheme),
                      _buildDayBubble('M', 1, scheme),
                      _buildDayBubble('T', 2, scheme),
                      _buildDayBubble('W', 3, scheme),
                      _buildDayBubble('T', 4, scheme),
                      _buildDayBubble('F', 5, scheme),
                      _buildDayBubble('S', 6, scheme),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Settings List
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alarm name',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('Topics'),
                  subtitle: Text(
                    bank.describe(_topics),
                    style: TextStyle(color: scheme.secondary),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickTopics,
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('Ringtone'),
                  subtitle: Text(_audioName, style: muted),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showRingtonePicker,
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('Fade-in Sound'),
                  subtitle: Text(
                    _fadeDuration == 0
                        ? 'None'
                        : '${_fadeDuration.toInt()} seconds',
                    style: muted,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showFadePicker,
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: const Text('Vibrate'),
                  value: _vibrate,
                  onChanged: (v) => setState(() => _vibrate = v),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('Snooze'),
                  subtitle: Text(
                    '5 minutes, only after 5 wrong answers in a row',
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (widget.existingAlarm != null)
            TextButton(
              onPressed: () {
                Provider.of<AlarmProvider>(
                  context,
                  listen: false,
                ).deleteAlarm(widget.existingAlarm!.id);
                Navigator.pop(context);
              },
              child: Text(
                'Delete Alarm',
                style: TextStyle(color: scheme.error, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayBubble(String label, int dayIndex, ColorScheme scheme) {
    final isSelected = _customDays.contains(dayIndex);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _customDays.remove(dayIndex);
          } else {
            _customDays.add(dayIndex);
          }
        });
      },
      child: CircleAvatar(
        radius: 20,
        backgroundColor: isSelected ? scheme.primary : scheme.surface,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getCustomDaysText() {
    if (_customDays.isEmpty) return 'No days picked: rings once';
    if (_customDays.length == 7) return 'Every day';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [..._customDays]..sort();
    return sorted.map((d) => names[d - 1]).join(', ');
  }
}
