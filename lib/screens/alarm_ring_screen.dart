/// Full-screen quiz shown while an alarm rings. The alarm's difficulty sets
/// how many correct answers in a row dismiss it; five wrong in a row unlock
/// the snooze (length chosen per alarm).
/// Questions come from the local database only, so it works offline.
/// Every ring is saved as a session for the Reports tab.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import '../services/alarm_provider.dart';
import '../services/question_service.dart';
import '../services/theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
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

enum _Phase { loading, asking, grading, correct, wrong, failed }

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  static const Color _baseColor = Color(0xFF140A1C);
  static const int _wrongForSnooze = 5;

  int _correctStreak = 0;
  int _wrongStreak = 0;
  _Phase _phase = _Phase.loading;
  Question? _currentQuestion;
  String _lastAnswer = '';
  final Set<String> _shown = {};
  final Stopwatch _questionTimer = Stopwatch();
  Future<int?>? _session;
  bool _closing = false;

  final TextEditingController _saqController = TextEditingController();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final StreamController<void> _shakeController =
      StreamController<void>.broadcast();
  Color _backgroundColor = _baseColor;

  int get _needed => widget.alarm.requiredStreak;

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
    if (!widget.preview) {
      // The alarm plays at full volume; swallow the volume keys so it
      // cannot be turned down without answering.
      HardwareKeyboard.instance.addHandler(_blockVolumeKeys);
      _session = QuestionRepository.startSession(
        'alarm',
        widget.alarm.label,
        alarmId: widget.alarm.id,
        requiredStreak: _needed,
      );
    }
    _loadNextQuestion();
  }

  bool _blockVolumeKeys(KeyEvent event) {
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.audioVolumeDown ||
        key == LogicalKeyboardKey.audioVolumeUp ||
        key == LogicalKeyboardKey.audioVolumeMute;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_blockVolumeKeys);
    _saqController.dispose();
    _sfxPlayer.dispose();
    _shakeController.close();
    super.dispose();
  }

  void _sfx(String name) {
    _sfxPlayer.play(AssetSource('sounds/$name.mp3')).catchError((_) {});
  }

  void _flash(Color color) {
    setState(() => _backgroundColor = color);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _backgroundColor = _baseColor);
    });
  }

  Future<void> _loadNextQuestion() async {
    setState(() => _phase = _Phase.loading);
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
    if (!mounted) return;
    setState(() {
      _currentQuestion = q;
      _phase = q == null ? _Phase.failed : _Phase.asking;
    });
    _questionTimer
      ..reset()
      ..start();
  }

  Future<void> _finish(String result) async {
    if (_closing) return;
    _closing = true;
    if (!widget.preview) {
      final provider = Provider.of<AlarmProvider>(context, listen: false);
      if (result == 'snooze') {
        await provider.snoozeAlarm(widget.alarm);
      } else {
        await provider.dismissAlarm(widget.alarm);
      }
      await QuestionRepository.endSession(
        await _session,
        result == 'snooze' ? 'snoozed' : 'dismissed',
      );
      QuestionService.changes.value++;
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _submitAnswer(String answer) async {
    final q = _currentQuestion;
    if (q == null || _phase != _Phase.asking || answer.trim().isEmpty) return;
    _questionTimer.stop();
    final taken = _questionTimer.elapsed;
    FocusScope.of(context).unfocus();
    setState(() {
      _phase = _Phase.grading;
      _lastAnswer = answer.trim();
    });

    final isCorrect = await QuestionService.gradeAnswer(q, answer);
    final session = await _session;
    unawaited(
      QuestionRepository.recordAttempt(
        q.id,
        correct: isCorrect,
        mode: widget.preview ? 'test' : 'alarm',
        sessionId: session,
        userAnswer: answer,
        timeTaken: taken,
      ),
    );
    if (!mounted) return;

    if (isCorrect) {
      _correctStreak++;
      _wrongStreak = 0;
      _sfx('correct');
      _flash(Colors.green.shade800);
      setState(() => _phase = _Phase.correct);
      // A short pause so the tick is seen, then straight on.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      if (_correctStreak >= _needed) {
        await _finish('dismissed');
      } else {
        await _loadNextQuestion();
      }
    } else {
      _correctStreak = 0;
      _wrongStreak++;
      _sfx('wrong');
      _shakeController.add(null);
      _flash(Colors.red.shade900);
      // Stay on the review card until the user taps "Next question".
      setState(() => _phase = _Phase.wrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This screen is always dark, whatever the app theme is.
    return Theme(
      data: AppTheme.dark,
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(child: _body()),
                        ),
                      ),
                      if (_wrongStreak >= _wrongForSnooze)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orangeAccent,
                              side: const BorderSide(
                                color: Colors.orangeAccent,
                              ),
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: () => _finish('snooze'),
                            icon: const Icon(Icons.snooze),
                            label: Text(
                              'Snooze (${widget.alarm.snoozeMinutes} minutes)',
                            ),
                          ),
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

  /// Streak progress, wrong-answer count and (in a test) the close button.
  Widget _header() {
    final use24 = context.watch<ThemeProvider>().use24Hour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.preview
                    ? '${widget.alarm.label} (test)'
                    : widget.alarm.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              formatClock(DateTime.now(), use24Hour: use24),
              style: const TextStyle(
                fontFamily: AppTheme.display,
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.bolt, color: Colors.amber, size: 20),
            const SizedBox(width: 4),
            Text(
              'Streak: $_correctStreak / $_needed',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            if (widget.preview)
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Close test'),
              )
            else
              Text(
                'Wrong: $_wrongStreak / $_wrongForSnooze',
                style: TextStyle(
                  color: _wrongStreak > 0 ? Colors.redAccent : Colors.white54,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _needed == 0 ? 0 : _correctStreak / _needed,
            minHeight: 8,
            color: AppColors.amber,
            backgroundColor: Colors.white12,
          ),
        ),
        if (widget.preview)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Wrong: $_wrongStreak / $_wrongForSnooze',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _wrongStreak > 0 ? Colors.redAccent : Colors.white54,
              ),
            ),
          ),
      ],
    );
  }

  Widget _body() {
    final q = _currentQuestion;
    switch (_phase) {
      case _Phase.loading:
      case _Phase.grading:
        return const CircularProgressIndicator();
      case _Phase.failed:
        return _loadFailed();
      case _Phase.correct:
        return _correctView();
      case _Phase.wrong:
        return _wrongView(q!);
      case _Phase.asking:
        return _questionView(q!);
    }
  }

  /// An alarm must always be dismissable, even if the bank cannot be read.
  Widget _loadFailed() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 40),
      const SizedBox(height: 12),
      const Text(
        'A question could not be loaded.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Colors.white),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _loadNextQuestion,
        child: const Text('Try again'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => _finish('dismissed'),
        child: const Text('Dismiss alarm'),
      ),
    ],
  );

  Widget _correctView() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_circle, color: Colors.greenAccent, size: 72),
      const SizedBox(height: 12),
      const Text(
        'Correct!',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _correctStreak >= _needed
            ? 'Alarm off. Good morning!'
            : '${_needed - _correctStreak} more to go',
        style: const TextStyle(color: Colors.white70, fontSize: 16),
      ),
    ],
  );

  /// Review of a wrong answer: what was asked, what was answered, the right
  /// answer and why. Stays until "Next question" is tapped.
  Widget _wrongView(Question q) {
    Widget answerBox({
      required String label,
      required String text,
      required Color color,
      required IconData icon,
    }) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.cancel, color: Colors.redAccent, size: 28),
              SizedBox(width: 8),
              Text(
                'Not quite',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              Text('Streak reset', style: TextStyle(color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            q.questionText,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 12),
          answerBox(
            label: 'YOUR ANSWER',
            text: _lastAnswer,
            color: Colors.redAccent,
            icon: Icons.close,
          ),
          answerBox(
            label: 'CORRECT ANSWER',
            text: q.correctAnswer,
            color: Colors.greenAccent,
            icon: Icons.check,
          ),
          if (q.explanation.trim().isNotEmpty) ...[
            const Text(
              'WHY',
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              q.explanation,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
            const SizedBox(height: 14),
          ],
          GradientButton(
            onPressed: _loadNextQuestion,
            icon: Icons.arrow_forward_rounded,
            label: 'Next question',
            height: 52,
          ),
        ],
      ),
    );
  }

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
          fontFamily: AppTheme.display,
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 20),
      if (q.type == QuestionType.mcq)
        for (final (i, opt) in q.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: Colors.white.withValues(alpha: 0.07),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _submitAnswer(opt),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      LetterBadge(index: i, color: AppColors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          opt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
      else ...[
        TextField(
          controller: _saqController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Type answer...'),
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
