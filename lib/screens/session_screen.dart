/// One past alarm or practice session: its totals, then every question
/// with what you answered, the correct answer, the explanation and how
/// long you took. Everything comes from the local database.
library;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import '../services/theme_provider.dart';
import 'tabs/reports_tab.dart' show formatDuration;

class SessionScreen extends StatefulWidget {
  final StudySession session;
  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  List<AttemptDetail>? _attempts;

  @override
  void initState() {
    super.initState();
    QuestionRepository.getSessionAttempts(widget.session.id).then((list) {
      if (mounted) setState(() => _attempts = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attempts = _attempts;
    final kind = switch (s.kind) {
      'alarm' => 'Alarm',
      'revision' => 'Free revision',
      _ => 'Question bank',
    };

    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: attempts == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '$kind - ${DateFormat('EEEE d MMMM').format(s.startedAt)}, '
                  '${formatClock(s.startedAt, use24Hour: context.watch<ThemeProvider>().use24Hour)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.kind == 'alarm')
                        _line('Result', switch (s.outcome) {
                          'dismissed' => 'Dismissed',
                          'snoozed' => 'Snoozed',
                          _ => 'Not finished',
                        }),
                      if (s.kind == 'alarm' && s.requiredStreak != null)
                        _line(
                          'Difficulty',
                          '${AlarmItem.difficultyName(s.requiredStreak!)} '
                              '(${s.requiredStreak} in a row)',
                        ),
                      _line(
                        s.kind == 'alarm'
                            ? 'Questions it took'
                            : 'Questions answered',
                        '${attempts.length}',
                      ),
                      _line(
                        'Correct',
                        '${attempts.where((a) => a.correct).length} '
                            'of ${attempts.length}',
                      ),
                      if (s.duration != null)
                        _line(
                          s.kind == 'alarm' ? 'Time to wake' : 'Time spent',
                          formatDuration(s.duration!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (attempts.isEmpty)
                  const Text('No answers were recorded in this session.'),
                for (var i = 0; i < attempts.length; i++)
                  _attemptCard(i + 1, attempts[i], theme),
              ],
            ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _attemptCard(int number, AttemptDetail a, ThemeData theme) {
    final scheme = theme.colorScheme;
    final color = a.correct ? Colors.green : scheme.error;
    final q = a.question;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  a.correct ? Icons.check_circle : Icons.cancel,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Question $number - ${q.topic}',
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (a.timeTaken != null)
                  Text(
                    formatDuration(a.timeTaken!),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              q.questionText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              a.userAnswer.isEmpty
                  ? "You answered: (I don't know)"
                  : 'You answered: ${a.userAnswer}',
              style: TextStyle(color: color),
            ),
            if (!a.correct)
              Text(
                'Correct answer: ${q.correctAnswer}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (q.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                q.explanation,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
