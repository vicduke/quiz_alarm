/// Flash-card practice: one question at a time; answer by picking or typing
/// (or "I don't know"), then the card shows the right answer and why.
///
/// - Question Bank uses it offline: the stored explanation is shown, with
///   an optional "Ask the AI tutor" button.
/// - Free Revision turns [aiTutor] on: the AI marks typed answers and
///   explains where the answer went wrong. If the AI can't be reached the
///   stored explanation is used, so a session never gets stuck.
library;

import 'package:material_ui/material_ui.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import '../services/gemini_client.dart';
import '../services/question_service.dart';

class PracticeScreen extends StatefulWidget {
  final String title;

  /// Topic or unit ids to draw from. Empty = every topic (random).
  final List<String> selectors;

  /// Ask the AI for feedback automatically after every answer.
  final bool aiTutor;

  /// Stored with each answer: 'revision' or 'bank'.
  final String mode;

  const PracticeScreen({
    super.key,
    required this.title,
    required this.selectors,
    this.aiTutor = false,
    this.mode = 'bank',
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

enum _Phase { loading, asking, checking, answered, empty }

class _PracticeScreenState extends State<PracticeScreen> {
  final _answerCtrl = TextEditingController();
  final Set<String> _shown = {};

  _Phase _phase = _Phase.loading;
  Question? _question;
  String _userAnswer = '';
  bool _verdict = false;

  bool _hasKey = false;
  bool _aiLoading = false;
  String? _aiText;
  String? _aiError;

  // Saved for the Reports tab; created on the first answer so that
  // opening and closing a session leaves nothing behind.
  Future<int?>? _session;
  int? _sessionId;
  final Stopwatch _timer = Stopwatch();

  int _answered = 0;
  int _correct = 0;

  @override
  void initState() {
    super.initState();
    GeminiClient.hasApiKey().then((v) {
      if (mounted) setState(() => _hasKey = v);
    });
    _next();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    QuestionRepository.endSession(
      _sessionId,
      'finished',
    ).then((_) => QuestionService.changes.value++);
    super.dispose();
  }

  Future<void> _next() async {
    setState(() => _phase = _Phase.loading);
    _answerCtrl.clear();
    final q = await QuestionService.nextQuestion(
      widget.selectors,
      exclude: _shown,
    );
    if (!mounted) return;
    setState(() {
      _question = q;
      _userAnswer = '';
      _aiText = null;
      _aiError = null;
      _aiLoading = false;
      _phase = q == null ? _Phase.empty : _Phase.asking;
    });
    if (q != null) _shown.add(q.id);
    _timer
      ..reset()
      ..start();
  }

  /// [answer] empty = "I don't know".
  Future<void> _submit(String answer) async {
    final q = _question;
    if (q == null || _phase != _Phase.asking) return;
    FocusScope.of(context).unfocus();
    _timer.stop();
    final taken = _timer.elapsed;
    final useAi = widget.aiTutor && _hasKey;
    final certain = QuestionService.certainVerdict(q, answer);

    setState(() {
      _userAnswer = answer.trim();
      _phase = _Phase.checking;
    });

    bool verdict;
    if (useAi && certain == null) {
      // A typed answer that is not word-for-word: the AI decides.
      try {
        final fb = await QuestionService.aiFeedback(q, answer);
        verdict = fb.correct;
        _aiText = fb.feedback;
      } catch (e) {
        verdict = isLocallyCorrect(q, answer);
        _aiError = e.toString();
      }
    } else {
      verdict = certain ?? isLocallyCorrect(q, answer);
    }
    if (!mounted || _question?.id != q.id) return;

    setState(() {
      _verdict = verdict;
      _phase = _Phase.answered;
      _answered++;
      if (verdict) _correct++;
    });
    _session ??= QuestionRepository.startSession(widget.mode, widget.title);
    _sessionId = await _session;
    await QuestionRepository.recordAttempt(
      q.id,
      correct: verdict,
      mode: widget.mode,
      sessionId: _sessionId,
      userAnswer: answer,
      timeTaken: taken,
    );
    QuestionService.changes.value++;

    if (useAi && _aiText == null && _aiError == null) {
      await _askTutor();
    }
  }

  Future<void> _askTutor() async {
    final q = _question;
    if (q == null || _aiLoading) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    String? text;
    String? error;
    try {
      final fb = await QuestionService.aiFeedback(
        q,
        _userAnswer,
        knownVerdict: _verdict,
      );
      text = fb.feedback;
    } catch (e) {
      error = e.toString();
    }
    if (!mounted || _question?.id != q.id) return;
    setState(() {
      _aiLoading = false;
      _aiText = text;
      _aiError = error;
    });
  }

  Future<void> _finish() async {
    if (_answered == 0) {
      Navigator.pop(context);
      return;
    }
    final percent = (_correct * 100 / _answered).round();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session finished'),
        content: Text(
          'You answered $_answered question${_answered == 1 ? '' : 's'} and '
          'got $_correct right ($percent%).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '$_correct / $_answered',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          TextButton(onPressed: _finish, child: const Text('Finish')),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.empty:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'There are no questions for this selection yet.\n\n'
              'Open the topic in Question Banks and tap "Generate with AI", '
              'or pick other topics.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      default:
        break;
    }

    final q = _question!;
    final scheme = Theme.of(context).colorScheme;
    final answered = _phase == _Phase.answered;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.topic.toUpperCase(),
                        style: TextStyle(
                          color: scheme.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        q.questionText,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (q.type == QuestionType.mcq)
                for (final o in q.options) _optionTile(q, o, scheme)
              else if (!answered)
                TextField(
                  controller: _answerCtrl,
                  enabled: _phase == _Phase.asking,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Your answer',
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _submit(v);
                  },
                ),
              if (_phase == _Phase.checking)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.topCenter,
                child: answered
                    ? _answerSide(q, scheme)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: answered
              ? FilledButton.icon(
                  onPressed: _next,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next question'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _phase == _Phase.asking
                            ? () => _submit('')
                            : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text("I don't know"),
                      ),
                    ),
                    if (q.type == QuestionType.saq) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _phase == _Phase.asking
                              ? () {
                                  if (_answerCtrl.text.trim().isNotEmpty) {
                                    _submit(_answerCtrl.text);
                                  }
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: const Text('Check'),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _optionTile(Question q, String option, ColorScheme scheme) {
    final answered = _phase == _Phase.answered;
    final isCorrect =
        option.toLowerCase() == q.correctAnswer.trim().toLowerCase();
    final isPicked = option == _userAnswer;

    Color? background;
    Color border = scheme.outlineVariant;
    IconData? icon;
    if (answered && isCorrect) {
      background = Colors.green.withValues(alpha: 0.18);
      border = Colors.green;
      icon = Icons.check_circle;
    } else if (answered && isPicked) {
      background = scheme.error.withValues(alpha: 0.16);
      border = scheme.error;
      icon = Icons.cancel;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background ?? scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _phase == _Phase.asking ? () => _submit(option) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(option, style: const TextStyle(fontSize: 16)),
                ),
                if (icon != null) Icon(icon, color: border, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The "back of the card": verdict, answer, explanation, AI tutor.
  Widget _answerSide(Question q, ColorScheme scheme) {
    final skipped = _userAnswer.isEmpty;
    final color = _verdict ? Colors.green : scheme.error;
    final hasExplanation = q.explanation.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              _verdict
                  ? Icons.check_circle
                  : (skipped ? Icons.lightbulb : Icons.cancel),
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              _verdict
                  ? 'Correct!'
                  : (skipped ? "Here's the answer" : 'Not quite'),
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (q.type == QuestionType.saq && !skipped)
          Text('Your answer: $_userAnswer'),
        if (q.type == QuestionType.saq || !_verdict)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Correct answer: ${q.correctAnswer}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        const SizedBox(height: 12),
        if (hasExplanation)
          _infoCard(
            scheme,
            icon: Icons.menu_book,
            title: 'Explanation',
            child: Text(q.explanation, style: const TextStyle(height: 1.4)),
          ),
        if (_aiLoading)
          _infoCard(
            scheme,
            icon: Icons.auto_awesome,
            title: 'AI tutor',
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Looking at your answer...'),
              ],
            ),
          )
        else if (_aiText != null)
          _infoCard(
            scheme,
            icon: Icons.auto_awesome,
            title: 'AI tutor',
            child: Text(_aiText!, style: const TextStyle(height: 1.4)),
          )
        else if (_aiError != null)
          _infoCard(
            scheme,
            icon: Icons.cloud_off,
            title: 'AI tutor unavailable',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasExplanation
                      ? 'Showing the saved explanation instead. ($_aiError)'
                      : _aiError!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: _askTutor,
                  child: const Text('Try again'),
                ),
              ],
            ),
          )
        else if (_hasKey)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _askTutor,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _verdict ? 'Ask the AI tutor for more' : 'Ask the AI tutor why',
              ),
            ),
          )
        else if (!hasExplanation)
          Text(
            'No explanation is saved for this question. Add a Gemini API key '
            'in Settings to get one from the AI tutor.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _infoCard(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
