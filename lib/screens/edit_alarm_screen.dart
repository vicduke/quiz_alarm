/// Add / edit one alarm: time, repeat days, name, topics, difficulty,
/// ringtone, volume, fade and snooze. Done is in the top right corner.
library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/alarm_provider.dart';
import '../services/bank_provider.dart';
import '../services/entitlements.dart';
import '../services/theme_provider.dart';
import '../widgets/lock_prompt.dart';
import '../widgets/time_wheel.dart';
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
      'name': 'Morning Marimba',
      'path': 'assets/sounds/ringtones/morning_marimba.mp3',
    },
    {'name': 'Piano Dawn', 'path': 'assets/sounds/ringtones/piano_dawn.mp3'},
    {'name': 'Music Box', 'path': 'assets/sounds/ringtones/music_box.mp3'},
    {
      'name': 'Kalimba Sunrise',
      'path': 'assets/sounds/ringtones/kalimba_sunrise.mp3',
    },
    {'name': 'Sunrise', 'path': 'assets/sounds/ringtones/sunrise_swell.mp3'},
    {'name': 'Upbeat', 'path': 'assets/sounds/ringtones/upbeat.mp3'},
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
  static const List<double> _fadeOptions = [
    0.0,
    5.0,
    10.0,
    30.0,
    60.0,
    120.0,
    150.0,
    180.0,
  ];

  /// "30 seconds", "1 minute", "2.5 minutes".
  static String _fadeLabel(double seconds) {
    if (seconds == 0) return 'None';
    if (seconds < 60) return '${seconds.toInt()} seconds';
    final minutes = seconds / 60;
    final text = minutes == minutes.roundToDouble()
        ? '${minutes.toInt()}'
        : minutes.toStringAsFixed(1);
    return '$text minute${minutes == 1 ? '' : 's'}';
  }

  late TimeOfDay _selectedTime;
  late final TextEditingController _labelCtrl;
  late List<String> _topics; // topic/section/unit ids; empty = all topics

  // A new alarm starts with no topics chosen: the user says what it asks
  // (which may be "all topics") before it can be saved.
  late bool _topicsChosen;

  /// The ringtone last chosen for any alarm: new alarms start with it.
  static const String lastRingtonePref = 'last_ringtone';
  late String _audioPath;
  late String _audioName;
  late bool _vibrate;
  late double _fadeDuration;
  late int _requiredStreak;
  late int _snoozeMinutes;

  /// The alarm's own volume (0.2 to 1.0). Only used on a paid plan; kept
  /// as it is otherwise, so it is still there when the plan comes back.
  late double _volume;

  // Plays ringtone previews in the picker.
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _previewing;

  int _repeatMode = 0; // 0 = Ring once, 1 = Custom
  List<int> _customDays = []; // 1=Mon, 7=Sun

  @override
  void initState() {
    super.initState();
    final a = widget.existingAlarm;
    // A new alarm starts at the time it is now, so the wheels only need
    // turning from here to the time wanted.
    _selectedTime = a?.time ?? TimeOfDay.now();
    _labelCtrl = TextEditingController(text: a?.label ?? 'Quiz Alarm');
    _topics = List.of(a?.topics ?? const []);
    _topicsChosen = a != null;
    _audioPath = a?.audioPath ?? 'assets/sounds/alarm.mp3';
    _audioName = _nameOf(_audioPath);
    if (a == null) _useLastRingtone();
    _vibrate = a?.vibrate ?? true;
    _fadeDuration = a?.fadeDuration ?? 30.0; // new alarms fade in gently
    _requiredStreak = a?.requiredStreak ?? AlarmItem.easyStreak;
    _snoozeMinutes = a?.snoozeMinutes ?? 5;
    _volume = (a?.volume ?? 1.0).clamp(AlarmProvider.minVolume, 1.0).toDouble();

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

  /// A new alarm takes the ringtone chosen last time (a bundled one or
  /// the user's own file), unless the user picks another here first.
  Future<void> _useLastRingtone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(lastRingtonePref);
      if (last == null || last == _audioPath) return;
      // A file of the user's own may have been removed since.
      if (!last.startsWith('assets/') && !await File(last).exists()) return;
      if (!mounted || _ringtoneTouched) return;
      setState(() {
        _audioPath = last;
        _audioName = _nameOf(last);
      });
    } catch (e) {
      debugPrint('Could not read the last ringtone: $e');
    }
  }

  // True once the user has picked a ringtone on this screen.
  bool _ringtoneTouched = false;

  String _nameOf(String path) {
    for (final tone in _defaultRingtones) {
      if (tone['path'] == path) return tone['name']!;
    }
    // Saved custom files are named "<timestamp>_<original name>".
    return path.split('/').last.replaceFirst(RegExp(r'^\d+_'), '');
  }

  List<int> get _activeDays => _repeatMode == 1 ? _customDays : const [];

  bool _sameDays(List<int> a, List<int> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  /// Whether the alarm will be switched on once saved. Editing the name
  /// or topics of a switched-off alarm must not switch it on. Changing
  /// when it rings does, as in other clock apps.
  bool get _willBeOn =>
      widget.existingAlarm == null ||
      widget.existingAlarm!.isEnabled ||
      widget.existingAlarm!.time != _selectedTime ||
      !_sameDays(widget.existingAlarm!.activeDays, _activeDays);

  void _saveAlarm() {
    final provider = Provider.of<AlarmProvider>(context, listen: false);
    // A new alarm above the plan's limit is not saved: say why instead.
    if (widget.existingAlarm == null && !provider.canAddAlarm) {
      showAlarmLimitSheet(context);
      return;
    }
    // What it asks must be chosen, not assumed.
    if (!_topicsChosen) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Choose the topics this alarm will ask about.'),
          ),
        );
      _pickTopics();
      return;
    }
    // Alarms set from now on start with this ringtone.
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(lastRingtonePref, _audioPath),
    );
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
      volume: _volume,
      requiredStreak: _requiredStreak,
      snoozeMinutes: _snoozeMinutes,
      isEnabled: _willBeOn,
    );

    // The confirmation shows on the screen underneath once the phone has
    // been told, so the time in it is the one really registered.
    final messenger = ScaffoldMessenger.of(context);
    final use24 = context.read<ThemeProvider>().use24Hour;
    final saved = widget.existingAlarm == null
        ? provider.addAlarm(newAlarm)
        : provider.updateAlarm(newAlarm);
    saved.then((_) {
      final next = newAlarm.isEnabled ? provider.nextRing(newAlarm) : null;
      if (next == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeAlarmSet(next, DateTime.now(), use24Hour: use24),
            ),
          ),
        );
    });
    Navigator.pop(context);
  }

  /// "Delete alarm" asks first: one stray tap must not lose an alarm.
  Future<void> _confirmDelete() async {
    final provider = context.read<AlarmProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this alarm?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    // A snoozed alarm cannot be deleted to get round the quiz.
    if (await provider.deleteAlarm(widget.existingAlarm!.id) > 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text(AlarmProvider.snoozeLockMessage)),
      );
    }
  }

  Future<void> _pickTopics() async {
    final bank = context.read<BankProvider>();
    final picked = await showTopicPickerSheet(
      context,
      // Nothing is ticked until the user has chosen.
      initial: _topicsChosen ? bank.selectedIds(_topics) : const <String>{},
      title: 'Topics for this alarm',
    );
    if (picked == null || !mounted) return;
    // Nothing ticked is not a choice: the alarm needs something to ask.
    if (picked.isEmpty) {
      setState(() => _topicsChosen = false);
      return;
    }
    // Every topic ticked is the same as "all topics", which also covers
    // topics added later. (Topics of archived units are not part of "all".)
    final everything = bank.openTopics.map((t) => t.id).toSet();
    final all =
        picked.length == everything.length && picked.containsAll(everything);
    // A whole unit, subunit or section is stored by its own id as well,
    // so that topics added to it later are asked too.
    setState(() {
      _topics = all ? [] : bank.selectorsFor(picked);
      _topicsChosen = true;
    });
  }

  /// The folder uploaded ringtones are kept in.
  Future<Directory> _ringtoneDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/ringtones');
  }

  /// Every ringtone uploaded so far (for any alarm), newest first.
  Future<List<File>> _loadUploads() async {
    if (kIsWeb) return [];
    try {
      final dir = await _ringtoneDir();
      if (!await dir.exists()) return [];
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (e) {
      debugPrint('Could not list uploaded ringtones: $e');
      return [];
    }
  }

  /// Removes an uploaded ringtone, unless an alarm still uses it.
  Future<bool> _deleteUpload(File file) async {
    final inUse =
        _audioPath == file.path ||
        context.read<AlarmProvider>().alarms.any(
          (a) => a.audioPath == file.path,
        );
    if (inUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An alarm uses this ringtone. Change it there first.'),
        ),
      );
      return false;
    }
    try {
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True if the audio file at [path] can be opened and has a length.
  Future<bool> _canPlay(String path) async {
    try {
      await _previewPlayer
          .setSource(DeviceFileSource(path))
          .timeout(const Duration(seconds: 8));
      final length = await _previewPlayer.getDuration();
      await _previewPlayer.stop();
      return length != null && length > Duration.zero;
    } catch (e) {
      debugPrint('Audio check failed: $e');
      return false;
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;
    // file_picker hands back a temporary cache copy the OS may delete.
    // Keep our own copy so the alarm never goes silent.
    try {
      final dir = await _ringtoneDir();
      await dir.create(recursive: true);
      final name = result.files.single.name;
      final dest = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
      await File(result.files.single.path!).copy(dest);
      // An alarm with a file the phone cannot play would be silent, so
      // check it plays before accepting it.
      if (!await _canPlay(dest)) {
        await File(dest).delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This phone cannot play that file. Try an MP3 or M4A.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _audioPath = dest;
        _audioName = name;
        _ringtoneTouched = true;
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

  Future<void> _showRingtonePicker() async {
    var uploads = await _loadUploads();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          Widget toneTile(String name, String path, {File? upload}) => ListTile(
            leading: IconButton(
              tooltip: 'Preview',
              icon: Icon(
                _previewing == path ? Icons.stop_circle : Icons.play_circle,
              ),
              onPressed: () => _togglePreview(path, refresh),
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_audioPath == path) const Icon(Icons.check),
                if (upload != null)
                  IconButton(
                    tooltip: 'Delete this upload',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (_previewing == path) await _stopPreview();
                      if (await _deleteUpload(upload)) {
                        uploads = await _loadUploads();
                        refresh(() {});
                      }
                    },
                  ),
              ],
            ),
            onTap: () {
              setState(() {
                _audioPath = path;
                _audioName = name;
                _ringtoneTouched = true;
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
                    'Ringtone',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tone in _defaultRingtones)
                          toneTile(tone['name']!, tone['path']!),
                        // Ringtones uploaded earlier stay available for
                        // every alarm.
                        if (uploads.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Your uploads',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleSmall,
                            ),
                          ),
                        for (final f in uploads)
                          toneTile(_nameOf(f.path), f.path, upload: f),
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
                'Mercy snooze',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  'The snooze button unlocks after '
                  '${AlarmItem.wrongAnswersForSnooze} wrong answers in a '
                  'row. One right answer resets that count. A wrong answer '
                  'also resets your streak of correct answers. A snoozed '
                  'alarm can be switched off on the Alarms tab only after '
                  'two snoozes.',
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

  /// "Medium: 3 in a row".
  String _difficultyText(int streak) =>
      '${AlarmItem.difficultyName(streak)}: $streak in a row';

  void _showDifficultyPicker() {
    const presets = AlarmItem.presetStreaks;
    const low = AlarmItem.customMinStreak;
    const high = AlarmItem.customMaxStreak;
    var custom = !presets.contains(_requiredStreak);
    var customValue = custom ? _requiredStreak.clamp(low, high) : low;

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
                    'A wrong answer resets the streak to zero.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                for (final streak in presets)
                  ListTile(
                    title: Text(AlarmItem.difficultyName(streak)),
                    // Says what the choice means before it is saved.
                    subtitle: Text(
                      '${AlarmItem.difficultyMeaning(streak)} '
                              '${AlarmItem.difficultyEffort(streak)}'
                          .trim(),
                    ),
                    trailing: !custom && _requiredStreak == streak
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => choose(streak, isCustom: false),
                  ),
                ListTile(
                  title: const Text('Custom'),
                  subtitle: Text(
                    custom
                        ? AlarmItem.difficultyMeaning(customValue)
                        : '$low to $high correct answers in a row.',
                  ),
                  trailing: custom ? const Icon(Icons.check) : null,
                  onTap: () => choose(customValue, isCustom: true),
                ),
                if (custom)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('$low'),
                        Expanded(
                          child: Slider(
                            min: low.toDouble(),
                            max: high.toDouble(),
                            divisions: high - low,
                            label: '$customValue',
                            value: customValue.toDouble(),
                            onChanged: (v) {
                              customValue = v.round();
                              choose(customValue, isCustom: true);
                            },
                          ),
                        ),
                        const Text('$high'),
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
      isScrollControlled: true,
      builder: (sheetContext) {
        // Scrolls on small screens: there are eight options.
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Fade-in',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                for (final duration in _fadeOptions)
                  ListTile(
                    title: Text(_fadeLabel(duration)),
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
        // The only Done on the screen. It sits up here so that small
        // screens keep their whole height for the settings.
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
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // Time Picker (Cupertino Style)
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: TimeWheel(
              initial: _selectedTime,
              use24Hour: MediaQuery.of(context).alwaysUse24HourFormat,
              onChanged: (t) => setState(() => _selectedTime = t),
            ),
          ),
          const SizedBox(height: 20),

          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Ring once')),
              ButtonSegment(value: 1, label: Text('Repeat')),
            ],
            selected: {_repeatMode},
            onSelectionChanged: (s) => setState(() {
              _repeatMode = s.first;
              // "Repeat" with no day ticked would ring only once, so
              // start from the usual choice: Monday to Friday.
              if (_repeatMode == 1 && _customDays.isEmpty) {
                _customDays = [1, 2, 3, 4, 5];
              }
            }),
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
                      // Monday first, like the alarm cards.
                      _buildDayBubble('M', 1, scheme),
                      _buildDayBubble('T', 2, scheme),
                      _buildDayBubble('W', 3, scheme),
                      _buildDayBubble('T', 4, scheme),
                      _buildDayBubble('F', 5, scheme),
                      _buildDayBubble('S', 6, scheme),
                      _buildDayBubble('S', 7, scheme),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Settings list. A Material, so the rows' tap ripples show.
          Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
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
                    _topicsChosen
                        ? bank.describe(_topics)
                        : 'None chosen yet. Tap to choose.',
                    style: TextStyle(
                      color: _topicsChosen ? scheme.secondary : scheme.error,
                    ),
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
                  title: const Text('Fade-in'),
                  subtitle: Text(_fadeLabel(_fadeDuration), style: muted),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showFadePicker,
                ),
                const Divider(height: 1, indent: 16),
                ListenableBuilder(
                  listenable: Entitlements.instance,
                  builder: (context, _) => _volumeRow(muted),
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
                    'Mercy snooze: $_snoozeMinutes minutes. Unlocks after '
                    '${AlarmItem.wrongAnswersForSnooze} wrong answers in a '
                    'row.',
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
              onPressed: _confirmDelete,
              child: Text(
                'Delete alarm',
                style: TextStyle(color: scheme.error, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  /// The alarm's volume: a slider on a paid plan, otherwise a locked row
  /// that says alarms ring at maximum.
  Widget _volumeRow(TextStyle muted) {
    if (!Entitlements.instance.canSetVolume) {
      return ListTile(
        title: const Text('Alarm volume: Maximum'),
        trailing: const Icon(Icons.lock_rounded, size: 20),
        onTap: () => showLockedSheet(
          context,
          title: 'Alarm volume',
          message: 'Choosing a quieter volume is part of Pro.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Alarm volume', style: TextStyle(fontSize: 16)),
              ),
              Text('${(_volume * 100).round()}%', style: muted),
            ],
          ),
          Slider(
            value: _volume,
            min: AlarmProvider.minVolume,
            max: 1.0,
            divisions: 8,
            label: '${(_volume * 100).round()}%',
            onChanged: (v) => setState(() => _volume = v),
          ),
          Text(
            'Rings at this volume and stays locked there. The volume keys '
            'cannot change it while it rings.',
            style: muted.copyWith(fontSize: 12),
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

  String _getCustomDaysText() => _customDays.isEmpty
      ? 'No days picked: rings once'
      : AlarmItem.describeDays(_customDays);
}
