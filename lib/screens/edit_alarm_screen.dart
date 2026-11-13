import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/alarm_provider.dart';

class EditAlarmScreen extends StatefulWidget {
  final AlarmItem? existingAlarm;

  const EditAlarmScreen({super.key, this.existingAlarm});

  @override
  State<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends State<EditAlarmScreen> {
  late TimeOfDay _selectedTime;
  late String _label;
  late String _topics;
  late String _audioPath;
  late String _audioName;
  late bool _vibrate;
  late double _fadeDuration;

  int _repeatMode = 0; // 0 = Ring once, 1 = Custom
  List<int> _customDays = []; // 1=Mon, 7=Sun

  // Preset ringtones (Make sure these files exist in your assets folder!)
  final List<Map<String, String>> _defaultRingtones = [
    {'name': 'Default Alarm', 'path': 'assets/sounds/alarm.mp3'},
    {'name': 'Correct Chime', 'path': 'assets/sounds/correct.mp3'},
    {'name': 'Wrong Buzzer', 'path': 'assets/sounds/wrong.mp3'},
  ];

  final List<double> _fadeOptions = [0.0, 5.0, 10.0, 30.0, 60.0];

  @override
  void initState() {
    super.initState();
    final a = widget.existingAlarm;
    _selectedTime = a != null ? a.time : TimeOfDay.now();
    _label = a?.label ?? 'Quiz Alarm';
    _topics = a?.topics.join(', ') ?? 'Pharmacology';
    _audioPath = a?.audioPath ?? 'assets/sounds/alarm.mp3';
    _audioName = a?.audioPath.split('/').last ?? 'Default Alarm';
    _vibrate = a?.vibrate ?? true;
    _fadeDuration = a?.fadeDuration ?? 5.0;

    if (a != null) {
      if (a.activeDays.isEmpty) {
        _repeatMode = 0; // Ring once
      } else {
        _repeatMode = 1; // Custom
        _customDays = List.from(a.activeDays);
      }
    } else {
      _repeatMode = 0; // Default to Ring once for new alarms
      _customDays = [];
    }
  }

  String _getTimeUntil() {
    final now = DateTime.now();
    DateTime next = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    final diff = next.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours == 0 && minutes == 0) return "Next alarm in less than a minute";
    return "Next alarm in ${hours > 0 ? '$hours hours ' : ''}$minutes minutes";
  }

  void _saveAlarm() {
    List<int> activeDays = [];
    if (_repeatMode == 1) activeDays = _customDays;

    final topicList = _topics
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final newAlarm = AlarmItem(
      id: widget.existingAlarm?.id ?? AlarmItem.generateSafeId(),
      time: _selectedTime,
      topics: topicList.isEmpty ? ['Pharmacology'] : topicList,
      label: _label.trim().isEmpty ? 'Quiz Alarm' : _label.trim(),
      audioPath: _audioPath,
      vibrate: _vibrate,
      activeDays: activeDays,
      fadeDuration: _fadeDuration,
    );

    final provider = Provider.of<AlarmProvider>(context, listen: false);
    if (widget.existingAlarm == null) {
      provider.addAlarm(newAlarm);
    } else {
      provider.updateAlarm(newAlarm);
    }
    Navigator.pop(context);
  }

  void _showRingtonePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF262628),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Select Ringtone',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ..._defaultRingtones.map(
                (tone) => ListTile(
                  title: Text(
                    tone['name']!,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _audioPath == tone['path']
                      ? const Icon(Icons.check, color: Colors.blueAccent)
                      : null,
                  onTap: () {
                    setState(() {
                      _audioPath = tone['path']!;
                      _audioName = tone['name']!;
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(
                  Icons.folder_open,
                  color: Colors.blueAccent,
                ),
                title: const Text(
                  'Pick from device...',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.audio,
                  );
                  if (result != null && result.files.single.path != null) {
                    // file_picker hands back a temporary cache copy the OS may
                    // delete. Keep our own copy so the alarm never goes silent.
                    try {
                      final docs = await getApplicationDocumentsDirectory();
                      final dir = Directory('${docs.path}/ringtones');
                      await dir.create(recursive: true);
                      final name = result.files.single.name;
                      final dest =
                          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
                      await File(result.files.single.path!).copy(dest);
                      if (!mounted) return;
                      setState(() {
                        _audioPath = dest;
                        _audioName = name;
                      });
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not save that audio file.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFadePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF262628),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Fade-in Duration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ..._fadeOptions.map(
                (duration) => ListTile(
                  title: Text(
                    duration == 0 ? 'None' : '${duration.toInt()} seconds',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _fadeDuration == duration
                      ? const Icon(Icons.check, color: Colors.blueAccent)
                      : null,
                  onTap: () {
                    setState(() => _fadeDuration = duration);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkCardColor = const Color(0xFF262628);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.blueAccent, fontSize: 16),
          ),
        ),
        leadingWidth: 80,
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
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Center(
            child: Text(
              _getTimeUntil(),
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),

          // Time Picker (Cupertino Style)
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: darkCardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: CupertinoTheme(
              data: const CupertinoThemeData(
                brightness: Brightness.dark,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(
                    color: Colors.white,
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
          const SizedBox(height: 24),

          // Repeat Mode Toggles (Ring once & Custom only)
          Row(
            children: [
              _buildSegment('Ring once', 0),
              _buildSegment('Custom', 1),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Days Selector
          if (_repeatMode == 1)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: darkCardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Repeat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getCustomDaysText(),
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildDayBubble('S', 7),
                      _buildDayBubble('M', 1),
                      _buildDayBubble('T', 2),
                      _buildDayBubble('W', 3),
                      _buildDayBubble('T', 4),
                      _buildDayBubble('F', 5),
                      _buildDayBubble('S', 6),
                    ],
                  ),
                ],
              ),
            ),

          if (_repeatMode == 1) const SizedBox(height: 16),

          // Settings List
          Container(
            decoration: BoxDecoration(
              color: darkCardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _buildTextFieldTile('Alarm name', _label, (v) => _label = v),
                const Divider(height: 1, indent: 16, color: Colors.white12),
                _buildTextFieldTile('Topics', _topics, (v) => _topics = v),
                const Divider(height: 1, indent: 16, color: Colors.white12),
                ListTile(
                  title: const Text('Ringtone'),
                  subtitle: Text(
                    _audioName,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showRingtonePicker,
                ),
                const Divider(height: 1, indent: 16, color: Colors.white12),
                ListTile(
                  title: const Text('Fade-in Sound'),
                  subtitle: Text(
                    _fadeDuration == 0
                        ? 'None'
                        : '${_fadeDuration.toInt()} seconds',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showFadePicker,
                ),
                const Divider(height: 1, indent: 16, color: Colors.white12),
                SwitchListTile(
                  title: const Text('Vibrate'),
                  activeThumbColor: Colors.blueAccent,
                  value: _vibrate,
                  onChanged: (v) => setState(() => _vibrate = v),
                ),
                const Divider(height: 1, indent: 16, color: Colors.white12),
                ListTile(
                  title: const Text('Snooze'),
                  subtitle: const Text(
                    '5 minutes, mercy limited',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          if (widget.existingAlarm != null)
            TextButton(
              onPressed: () {
                Provider.of<AlarmProvider>(
                  context,
                  listen: false,
                ).deleteAlarm(widget.existingAlarm!.id);
                Navigator.pop(context);
              },
              child: const Text(
                'Delete Alarm',
                style: TextStyle(color: Colors.redAccent, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegment(String text, int index) {
    final isSelected = _repeatMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _repeatMode = index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent : const Color(0xFF333333),
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayBubble(String label, int dayIndex) {
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
        backgroundColor: isSelected
            ? Colors.blueAccent
            : const Color(0xFF444444),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldTile(
    String label,
    String initialValue,
    Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: TextEditingController(text: initialValue),
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          border: InputBorder.none,
        ),
      ),
    );
  }

  String _getCustomDaysText() {
    if (_customDays.isEmpty) return 'Never';
    if (_customDays.length == 7) return 'Every day';
    List<String> days = [];
    if (_customDays.contains(1)) days.add('Mon');
    if (_customDays.contains(2)) days.add('Tue');
    if (_customDays.contains(3)) days.add('Wed');
    if (_customDays.contains(4)) days.add('Thu');
    if (_customDays.contains(5)) days.add('Fri');
    if (_customDays.contains(6)) days.add('Sat');
    if (_customDays.contains(7)) days.add('Sun');
    return days.join(', ');
  }
}
