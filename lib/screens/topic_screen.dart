/// One topic of the question bank: practise it, add questions with AI,
/// and browse every question with its answer and explanation.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import '../services/bank_provider.dart';
import '../services/gemini_client.dart';
import '../services/question_service.dart';
import 'practice_screen.dart';

class TopicScreen extends StatefulWidget {
  final Topic topic;
  const TopicScreen({super.key, required this.topic});

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  List<Question>? _questions;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await QuestionRepository.getQuestions(widget.topic.id);
    if (mounted) setState(() => _questions = list);
  }

  void _message(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    if (!await GeminiClient.hasApiKey()) {
      if (mounted) {
        _message(
          'API key needed',
          'Add your Gemini API key in Settings (the gear icon on the home '
              'screen) to generate questions.',
        );
      }
      return;
    }
    setState(() => _generating = true);
    final result = await QuestionService.generateForTopic(widget.topic);
    if (!mounted) return;
    setState(() => _generating = false);
    await _load();
    if (!mounted) return;
    if (result.error != null) {
      _message('Could not generate questions', result.error!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${result.added} new question(s).')),
      );
    }
  }

  Future<void> _deleteQuestion(Question q) async {
    await QuestionRepository.deleteQuestion(q.id);
    QuestionService.changes.value++;
    await _load();
  }

  Future<void> _deleteTopic() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${widget.topic.name}"?'),
        content: const Text('The topic and all its questions will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await QuestionRepository.deleteCustomTopic(widget.topic.id);
    QuestionService.changes.value++;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<BankProvider>().statsOf(widget.topic.id);
    final theme = Theme.of(context);
    final questions = _questions;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.name),
        actions: [
          if (widget.topic.isCustom)
            IconButton(
              tooltip: 'Delete topic',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteTopic,
            ),
        ],
      ),
      body: questions == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${stats.total} questions - ${stats.seen} answered - '
                  '${stats.mastered} correct on the last try',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: questions.isEmpty
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PracticeScreen(
                                title: widget.topic.name,
                                selectors: [widget.topic.id],
                              ),
                            ),
                          );
                          _load();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Practise this topic'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _generating
                        ? 'Writing questions (up to a minute)...'
                        : 'Generate 5 more with AI',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 16),
                Text('All questions', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                if (questions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No questions in this topic yet.'),
                  ),
                for (final q in questions)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text(q.questionText),
                      subtitle: Text(
                        '${q.type == QuestionType.mcq ? 'Multiple choice' : 'Short answer'}'
                        '${q.source == 'ai' ? ' - AI generated' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        for (final o in q.options)
                          Text(
                            '${o == q.correctAnswer ? '✓' : '•'} $o',
                            style: TextStyle(
                              fontWeight: o == q.correctAnswer
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        if (q.options.isEmpty)
                          Text(
                            'Answer: ${q.correctAnswer}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          q.explanation.isEmpty
                              ? 'No explanation saved yet.'
                              : q.explanation,
                          style: const TextStyle(height: 1.4),
                        ),
                        if (q.source != 'seed')
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _deleteQuestion(q),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Remove'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
