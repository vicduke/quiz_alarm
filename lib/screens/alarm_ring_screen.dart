import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/alarm_provider.dart';
import '../services/question_service.dart';
import '../widgets/shake_widget.dart';

class AlarmRingScreen extends StatefulWidget {
  final AlarmItem alarm;
  const AlarmRingScreen({super.key, required this.alarm});

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  int _correctStreak = 0;
  int _wrongStreak = 0;
  Question? _currentQuestion;
  bool _isLoading = true;
  String? _feedbackMessage;
  Color _feedbackColor = Colors.transparent;
  final TextEditingController _saqController = TextEditingController();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final StreamController<void> _shakeController =
      StreamController<void>.broadcast();
  Color _backgroundColor = const Color(0xFF1A090D);

  @override
  void initState() {
    super.initState();
    _sfxPlayer.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ),
    );
    _loadNextQuestion();
  }

  @override
  void dispose() {
    _saqController.dispose();
    _sfxPlayer.dispose();
    _shakeController.close();
    super.dispose();
  }

  Future<void> _loadNextQuestion() async {
    setState(() => _isLoading = true);
    _saqController.clear();
    final q = await QuestionService.getNextQuestion(widget.alarm.topics);
    if (mounted) {
      setState(() {
        _currentQuestion = q;
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAnswer(String answer) async {
    if (_currentQuestion == null || _isLoading) return;
    setState(() => _isLoading = true);
    final isCorrect = await QuestionService.gradeAnswer(
      _currentQuestion!,
      answer,
    );
    if (!mounted) return;

    if (isCorrect) {
      _correctStreak++;
      _wrongStreak = 0;
      _feedbackMessage = 'Correct! ($_correctStreak/2)';
      _feedbackColor = Colors.green;
      _sfxPlayer.play(AssetSource('sounds/correct.mp3'));
      setState(() => _backgroundColor = Colors.green.shade800);

      if (_correctStreak >= 2) {
        await Provider.of<AlarmProvider>(
          context,
          listen: false,
        ).dismissAlarm(widget.alarm);
        if (mounted) Navigator.of(context).pop('dismissed');
        return;
      }
    } else {
      _correctStreak = 0;
      _wrongStreak++;
      _feedbackMessage =
          'Wrong! Expected: "${_currentQuestion!.correctAnswer}"';
      _feedbackColor = Colors.redAccent;
      _sfxPlayer.play(AssetSource('sounds/wrong.mp3'));
      _shakeController.add(null);
      setState(() => _backgroundColor = Colors.red.shade900);
    }

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _backgroundColor = const Color(0xFF1A090D));
    });
    await _loadNextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
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
                    const Spacer(),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_currentQuestion != null) ...[
                      Text(
                        'TOPIC: ${_currentQuestion!.topic.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _currentQuestion!.questionText,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_currentQuestion!.type == QuestionType.mcq)
                        ..._currentQuestion!.options.map(
                          (opt) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: ElevatedButton(
                              onPressed: () => _submitAnswer(opt),
                              child: Text(opt),
                            ),
                          ),
                        )
                      else ...[
                        TextField(
                          controller: _saqController,
                          decoration: const InputDecoration(
                            hintText: 'Type answer...',
                          ),
                          onSubmitted: _submitAnswer,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _submitAnswer(_saqController.text),
                          child: const Text('Submit'),
                        ),
                      ],
                    ],
                    const Spacer(),
                    if (_wrongStreak >= 5)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                        ),
                        onPressed: () async {
                          await Provider.of<AlarmProvider>(
                            context,
                            listen: false,
                          ).snoozeAlarm(widget.alarm);
                          if (mounted) Navigator.pop(context, 'snooze');
                        },
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
    );
  }
}
