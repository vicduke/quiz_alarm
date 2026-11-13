/// Full-screen quiz shown while an alarm rings. Two correct answers in a
/// row dismiss it; five wrong in a row unlock a 5-minute snooze.
/// Questions come from the local database only, so it works offline.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import '../services/alarm_provider.dart';
import '../services/question_service.dart';
import '../widgets/shake_widget.dart';

class AlarmRingScreen extends StatefulWidget {
  final AlarmItem alarm;

  /// True for "Test Alarm Screen": nothing is ringing, the screen can be
  /// closed, and finishing it does not touch any real alarm.
  final bool preview;

  const AlarmRingScreen({super.key, required this.alarm, this.preview = false});

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  static const Color _baseColor = Color(0xFF1A090D);

  int _correctStreak = 0;
  int _wrongStreak = 0;
  Question? _currentQuestion;
  bool _isLoading = true;
  String? _feedbackMessage;
  Color _feedbackColor = Colors.transparent;
  final Set<String> _shown = {};
  final TextEditingController _saqController = TextEditingController();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final StreamController<void> _shakeController =
      StreamController<void>.broadcast();
  Color _backgroundColor = _baseColor;

  @override
  void initState() {
    super.initState();
    _sfxPlayer
        .setAudioContext(
          AudioContext(
            android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
          ),
        )
        .catchError((_) {});
    _loadNextQuestion();
  }

  @override
  void dispose() {
    _saqController.dispose();
    _sfxPlayer.dispose();
    _shakeController.close();
    super.dispose();
  }

  void _sfx(String name) {
    _sfxPlayer.play(AssetSource('sounds/$name.mp3')).catchError((_) {});
  }

  Future<void> _loadNextQuestion() async {
    setState(() => _isLoading = true);
    _saqController.clear();
    Question? q;
    try {
      q = await QuestionService.nextQuestion(
        widget.alarm.topics,
        exclude: _shown,
      );
    } catch (e) {
      debugPrint('Could not load a question: $e');
    }
    if (q != null) _shown.add(q.id);
    if (mounted) {
      setState(() {
        _currentQuestion = q;
        _isLoading = false;
      });
    }
  }

  Future<void> _finish(String result) async {
    if (!widget.preview) {
      final provider = Provider.of<AlarmProvider>(context, listen: false);
      if (result == 'snooze') {
        await provider.snoozeAlarm(widget.alarm);
      } else {
        await provider.dismissAlarm(widget.alarm);
      }
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _submitAnswer(String answer) async {
    final q = _currentQuestion;
    if (q == null || _isLoading || answer.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final isCorrect = await QuestionService.gradeAnswer(q, answer);
    unawaited(
      QuestionRepository.recordAttempt(q.id, correct: isCorrect, mode: 'alarm'),
    );
    if (!mounted) return;

    if (isCorrect) {
      _correctStreak++;
      _wrongStreak = 0;
      _feedbackMessage = 'Correct! ($_correctStreak/2)';
      _feedbackColor = Colors.greenAccent;
      _sfx('correct');
      setState(() => _backgroundColor = Colors.green.shade800);

      if (_correctStreak >= 2) {
        await _finish('dismissed');
        return;
      }
    } else {
      _correctStreak = 0;
      _wrongStreak++;
      _feedbackMessage = 'Wrong! Expected: "${q.correctAnswer}"';
      _feedbackColor = Colors.redAccent;
      _sfx('wrong');
      _shakeController.add(null);
      setState(() => _backgroundColor = Colors.red.shade900);
    }

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _backgroundColor = _baseColor);
    });
    await _loadNextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final q = _currentQuestion;
    // This screen is always dark, whatever the app theme is.
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
        ),
      ),
      child: PopScope(
        canPop: widget.preview,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: _backgroundColor,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: ShakeWidget(
                shakeStream: _shakeController.stream,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.bolt, color: Colors.amber),
                            label: Text('Streak: $_correctStreak / 2'),
                          ),
                          if (widget.preview)
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                              label: const Text('Close test'),
                            ),
                          Chip(
                            avatar: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                            ),
                            label: Text('Wrong: $_wrongStreak / 5'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_feedbackMessage != null)
                        Text(
                          _feedbackMessage!,
                          style: TextStyle(
                            color: _feedbackColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : q == null
                                ? _emptyBank()
                                : _questionView(q),
                          ),
                        ),
                      ),
                      if (_wrongStreak >= 5)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _finish('snooze'),
                          icon: const Icon(Icons.snooze),
                          label: const Text('Mercy Snooze (5 Minutes)'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Should never happen (the app ships with questions), but an alarm
  /// must always be dismissable.
  Widget _emptyBank() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'The question bank is empty, so there is nothing to ask.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => _finish('dismissed'),
        child: const Text('Dismiss alarm'),
      ),
    ],
  );

  Widget _questionView(Question q) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'TOPIC: ${q.topic.toUpperCase()}',
        style: const TextStyle(
          color: Colors.amberAccent,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        q.questionText,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 24),
      if (q.type == QuestionType.mcq)
        ...q.options.map(
          (opt) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: FilledButton.tonal(
              onPressed: () => _submitAnswer(opt),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              child: Text(opt, textAlign: TextAlign.center),
            ),
          ),
        )
      else ...[
        TextField(
          controller: _saqController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Type answer...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: _submitAnswer,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _submitAnswer(_saqController.text),
          child: const Text('Submit'),
        ),
      ],
    ],
  );
}
