/// Reports tab: how you are doing over time, which topics are weak, how
/// long alarms take to dismiss, and the history of every alarm and
/// practice session (tap one to see its questions and explanations).
library;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/question_repository.dart';
import '../../models/models.dart';
import '../../services/question_service.dart';
import '../session_screen.dart';

/// "1m 20s", "45s" or "2h 5m".
String formatDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  ReportSummary? _report;
  List<StudySession> _sessions = [];
  String? _kind; // null = all
  String? _error;

  @override
  void initState() {
    super.initState();
    QuestionService.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    QuestionService.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final report = await QuestionRepository.getReport();
      final sessions = await QuestionRepository.getSessions(kind: _kind);
      if (!mounted) return;
      setState(() {
        _report = report;
        _sessions = sessions;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Reports could not be loaded: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (report == null) return const Center(child: CircularProgressIndicator());

    final accuracy = report.answered == 0
        ? null
        : (report.correct * 100 / report.answered).round();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _StatTile(
                label: 'Questions answered',
                value: '${report.answered}',
              ),
              const SizedBox(width: 12),
              _StatTile(
                label: 'Correct',
                value: accuracy == null ? '-' : '$accuracy%',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile(
                label: 'Average time to wake',
                value: report.avgWakeTime == null
                    ? '-'
                    : formatDuration(report.avgWakeTime!),
              ),
              const SizedBox(width: 12),
              _StatTile(
                label: 'Questions per alarm',
                value: report.avgWakeQuestions == null
                    ? '-'
                    : report.avgWakeQuestions!.toStringAsFixed(1),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              report.alarmsDismissed == 0
                  ? 'The alarm figures fill in after your first alarm.'
                  : 'Alarm figures are averages over '
                        '${report.alarmsDismissed} dismissed '
                        'alarm${report.alarmsDismissed == 1 ? '' : 's'}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 20),
          Text('Last 14 days', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _DayChart(days: report.days),
          const SizedBox(height: 20),
          Text('By topic', style: theme.textTheme.titleMedium),
          Text(
            'Weakest first. Counts every answer you have given.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (report.topics.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing answered yet.'),
            ),
          for (final t in report.topics) _TopicRow(topic: t),
          const SizedBox(height: 20),
          Text('History', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'alarm', label: Text('Alarms')),
              ButtonSegment(value: 'revision', label: Text('Revision')),
              ButtonSegment(value: 'bank', label: Text('Banks')),
            ],
            selected: {_kind ?? 'all'},
            onSelectionChanged: (s) {
              _kind = s.first == 'all' ? null : s.first;
              _load();
            },
          ),
          const SizedBox(height: 8),
          if (_sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No sessions yet. Alarms and practice sessions appear here.',
              ),
            ),
          for (final s in _sessions) _SessionCard(session: s),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// One bar per day: full height = answers that day, green part = correct.
class _DayChart extends StatelessWidget {
  final List<DayStat> days;
  const _DayChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peak = days.fold<int>(0, (m, d) => d.answered > m ? d.answered : m);
    const height = 110.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: peak == 0
                ? const Center(child: Text('No answers in this period yet.'))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in days)
                        Expanded(
                          child: Tooltip(
                            message:
                                '${DateFormat('d MMM').format(d.day)}: '
                                '${d.correct} of ${d.answered} correct',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height:
                                          height *
                                          (d.answered - d.correct) /
                                          peak,
                                      color: scheme.error.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                    Container(
                                      height: height * d.correct / peak,
                                      color: Colors.green,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: Text(
                    '${d.day.day}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 10, height: 10, color: Colors.green),
              const SizedBox(width: 4),
              Text('Correct', style: theme.textTheme.labelSmall),
              const SizedBox(width: 14),
              Container(
                width: 10,
                height: 10,
                color: scheme.error.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 4),
              Text('Wrong', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final TopicAccuracy topic;
  const _TopicRow({required this.topic});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(topic.topic)),
              Text(
                '${(topic.accuracy * 100).round()}%  '
                '(${topic.correct}/${topic.answered})',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: topic.accuracy,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
            color: topic.accuracy >= 0.7
                ? Colors.green
                : (topic.accuracy >= 0.4 ? Colors.orange : Colors.red),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final StudySession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final icon = switch (s.kind) {
      'alarm' => Icons.alarm,
      'revision' => Icons.school,
      _ => Icons.library_books,
    };
    final outcome = switch (s.outcome) {
      'dismissed' => 'Dismissed',
      'snoozed' => 'Snoozed',
      'finished' => null,
      _ => s.kind == 'alarm' ? 'Not finished' : null,
    };
    final parts = [
      '${s.questions} question${s.questions == 1 ? '' : 's'}',
      '${s.correct} correct',
      if (s.duration != null) formatDuration(s.duration!),
      ?outcome,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon),
        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${DateFormat('EEE d MMM, HH:mm').format(s.startedAt)}\n'
          '${parts.join(' - ')}',
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SessionScreen(session: s)),
        ),
      ),
    );
  }
}
