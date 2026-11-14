/// Add / edit one alarm: time, repeat days, name, topics, ringtone, fade.
library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/alarm_provider.dart';
import '../services/bank_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/topic_picker.dart';

class EditAlarmScreen extends StatefulWidget {
  final AlarmItem? existingAlarm;

  const EditAlarmScreen({super.key, this.existingAlarm});

  @override
  State<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends State<EditAlarmScreen> {
  // Preset ringtones, bundled in assets/sounds (the ones in ringtones/
  // are made by tool/make_ringtones.py).
  static const List<Map<String, String>> _defaultRingtones = [
    {'name': 'Default Alarm', 'path': 'assets/sounds/alarm.mp3'},
    {
      'name': 'Classic Beep',
      'path': 'assets/sounds/ringtones/classic_beep.mp3',
    },
    {'name': 'Digital', 'path': 'assets/sounds/ringtones/digital.mp3'},
    {
      'name': 'Gentle Chime',
      'path': 'assets/sounds/ringtones/gentle_chime.mp3',
    },
    {'name': 'Rising', 'path': 'assets/sounds/ringtones/rising.mp3'},
    {'name': 'Siren', 'path': 'assets/sounds/ringtones/siren.mp3'},
    {'name': 'Bell Tower', 'path': 'assets/sounds/ringtones/bell_tower.mp3'},
  ];
  static const List<double> _fadeOptions = [0.0, 5.0, 10.0, 30.0, 60.0];

  late TimeOfDay _selectedTime;
  late final TextEditingController _labelCtrl;
  late List<String> _topics; // topic/unit ids; empty = all topics
  late String _audioPath;
  late String _audioName;
  late bool _vibrate;
  late double _fadeDuration;
  late int _requiredStreak;
  late int _snoozeMinutes;

  // Plays ringtone previews in the picker.
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _previewing;

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
    _requiredStreak = a?.requiredStreak ?? 2;
    _snoozeMinutes = a?.snoozeMinutes ?? 5;

    if (a != null && a.activeDays.isNotEmpty) {
      _repeatMode = 1;
      _customDays = List.from(a.activeDays);
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _previewPlayer.dispose();
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
      requiredStreak: _requiredStreak,
      snoozeMinutes: _snoozeMinutes,
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

  Future<void> _stopPreview() async {
    _previewing = null;
    try {
      await _previewPlayer.stop();
    } catch (_) {}
  }

  /// Plays [path] once, or stops it if it is the one playing.
  Future<void> _togglePreview(String path, StateSetter refresh) async {
    if (_previewing == path) {
      await _stopPreview();
      refresh(() {});
      return;
    }
    refresh(() => _previewing = path);
    try {
      await _previewPlayer.stop();
      await _previewPlayer.play(
        path.startsWith('assets/')
            ? AssetSource(path.substring('assets/'.length))
            : DeviceFileSource(path),
      );
    } catch (e) {
      debugPrint('Ringtone preview failed: $e');
    }
  }

  void _showRingtonePicker() {
    final custom = !_defaultRingtones.any((t) => t['path'] == _audioPath);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          Widget toneTile(String name, String path) => ListTile(
            leading: IconButton(
              tooltip: 'Preview',
              icon: Icon(
                _previewing == path ? Icons.stop_circle : Icons.play_circle,
              ),
              onPressed: () => _togglePreview(path, refresh),
            ),
            title: Text(name),
            trailing: _audioPath == path ? const Icon(Icons.check) : null,
            onTap: () {
              setState(() {
                _audioPath = path;
                _audioName = name;
              });
              refresh(() {});
            },
          );

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Ringtone',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tone in _defaultRingtones)
                          toneTile(tone['name']!, tone['path']!),
                        if (custom) toneTile(_audioName, _audioPath),
                        const Divider(),
                        ListTile(
                          leading: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.upload_file),
                          ),
                          title: const Text('Upload from phone files...'),
                          // Copying a picked file needs real file storage.
                          subtitle: kIsWeb
                              ? const Text('Available in the phone app')
                              : const Text('Any audio file (mp3, m4a, wav...)'),
                          enabled: !kIsWeb,
                          onTap: () async {
                            await _stopPreview();
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            _pickAudioFile();
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(_stopPreview);
  }

  void _showSnoozePicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Snooze length',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  'The snooze button appears after 5 wrong answers in a row.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              for (final minutes in AlarmItem.snoozeChoices)
                ListTile(
                  title: Text('$minutes minutes'),
                  trailing: _snoozeMinutes == minutes
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() => _snoozeMinutes = minutes);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _difficultyText(int streak) =>
      '${AlarmItem.difficultyName(streak)}: $streak correct in a row';

  void _showDifficultyPicker() {
    const presets = [2, 3, 5];
    var custom = !presets.contains(_requiredStreak);
    var customValue = custom ? _requiredStreak.clamp(6, 15) : 6;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          void choose(int streak, {required bool isCustom}) {
            refresh(() => custom = isCustom);
            setState(() => _requiredStreak = streak);
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Difficulty',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Text(
                    'How many questions you must get right in a row to '
                    'switch the alarm off. A wrong answer restarts the count.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                for (final streak in presets)
                  ListTile(
                    title: Text(AlarmItem.difficultyName(streak)),
                    subtitle: Text('$streak correct in a row'),
                    trailing: !custom && _requiredStreak == streak
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => choose(streak, isCustom: false),
                  ),
                ListTile(
                  title: const Text('Custom'),
                  subtitle: Text(
                    custom
                        ? '$customValue correct in a row'
                        : '6 to 15 correct in a row',
                  ),
                  trailing: custom ? const Icon(Icons.check) : null,
                  onTap: () => choose(customValue, isCustom: true),
                ),
                if (custom)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('6'),
                        Expanded(
                          child: Slider(
                            min: 6,
                            max: 15,
                            divisions: 9,
                            label: '$customValue',
                            value: customValue.toDouble(),
                            onChanged: (v) {
                              customValue = v.round();
                              choose(customValue, isCustom: true);
                            },
                          ),
                        ),
                        const Text('15'),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
                    fontSize: 26,
                    fontFamily: AppTheme.display,
                  ),
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
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
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
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
                  title: const Text('Difficulty'),
                  subtitle: Text(
                    _difficultyText(_requiredStreak),
                    style: muted,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showDifficultyPicker,
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
                    '$_snoozeMinutes minutes, after 5 wrong answers in a row',
                    style: muted,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showSnoozePicker,
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
