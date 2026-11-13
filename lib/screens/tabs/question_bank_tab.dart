/// Question Banks tab: units and their topics with progress. Tap a topic
/// to practise it offline, browse its questions or add more with AI.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/question_repository.dart';
import '../../models/models.dart';
import '../../services/bank_provider.dart';
import '../practice_screen.dart';
import '../topic_screen.dart';

class QuestionBankTab extends StatelessWidget {
  const QuestionBankTab({super.key});

  Future<void> _addTopic(BuildContext context, BankProvider bank) async {
    final nameCtrl = TextEditingController();
    String unitId = QuestionRepository.customUnitId;
    final created = await showDialog<Topic>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add a topic'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Topic name',
                  hintText: 'e.g. Antimalarial drugs',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: unitId,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [
                  for (final u in bank.units)
                    if (u.id != QuestionRepository.customUnitId)
                      DropdownMenuItem(value: u.id, child: Text(u.name)),
                  const DropdownMenuItem(
                    value: QuestionRepository.customUnitId,
                    child: Text('My topics'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => unitId = v ?? unitId),
              ),
              const SizedBox(height: 12),
              Text(
                'New topics start empty. Open the topic and tap '
                '"Generate with AI" to fill it.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final t = await QuestionRepository.addCustomTopic(
                  name,
                  unitId: unitId,
                );
                if (ctx.mounted) Navigator.pop(ctx, t);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (created == null) return;
    await bank.reload();
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TopicScreen(topic: created)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankProvider>();
    final theme = Theme.of(context);

    if (bank.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (bank.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(bank.error!, textAlign: TextAlign.center),
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          children: [
            for (final unit in bank.units) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(unit.name, style: theme.textTheme.titleLarge),
                          Text(
                            '${bank.topicsOf(unit.id).length} topics, '
                            '${bank.topicsOf(unit.id).fold<int>(0, (n, t) => n + bank.statsOf(t.id).total)} questions',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: bank.topicsOf(unit.id).isEmpty
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PracticeScreen(
                                  title: unit.name,
                                  selectors: [unit.id],
                                ),
                              ),
                            ),
                      child: const Text('Practise all'),
                    ),
                  ],
                ),
              ),
              for (final topic in bank.topicsOf(unit.id))
                _TopicCard(topic: topic, stats: bank.statsOf(topic.id)),
            ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-topic',
            onPressed: () => _addTopic(context, bank),
            icon: const Icon(Icons.add),
            label: const Text('Add topic'),
          ),
        ),
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  final Topic topic;
  final TopicStats stats;
  const _TopicCard({required this.topic, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TopicScreen(topic: topic)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topic.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      stats.total == 0
                          ? 'No questions yet'
                          : '${stats.total} questions - ${stats.seen} answered - '
                                '${stats.mastered} correct',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: stats.total == 0
                          ? 0
                          : stats.mastered / stats.total,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 5,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
