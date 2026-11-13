/// Multi-select list of topics grouped by unit. Used when choosing what an
/// alarm asks about and what a revision session covers.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/bank_provider.dart';

class TopicPicker extends StatelessWidget {
  /// Ids of the topics that are ticked.
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const TopicPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankProvider>();
    if (bank.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final unit in bank.units) ...[
          Builder(
            builder: (context) {
              final ids = bank.topicsOf(unit.id).map((t) => t.id).toSet();
              final all = ids.isNotEmpty && selected.containsAll(ids);
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      unit.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: ids.isEmpty
                        ? null
                        : () => onChanged(
                            all
                                ? selected.difference(ids)
                                : selected.union(ids),
                          ),
                    child: Text(all ? 'Clear' : 'Select all'),
                  ),
                ],
              );
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in bank.topicsOf(unit.id))
                FilterChip(
                  label: Text('${t.name} (${bank.statsOf(t.id).total})'),
                  selected: selected.contains(t.id),
                  onSelected: (on) => onChanged(
                    on ? {...selected, t.id} : selected.difference({t.id}),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Opens [TopicPicker] in a bottom sheet. Returns the chosen topic ids
/// (empty = all topics), or null if the sheet was dismissed.
Future<Set<String>?> showTopicPickerSheet(
  BuildContext context, {
  required Set<String> initial,
  String title = 'Topics',
}) {
  var current = {...initial};
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  current.isEmpty
                      ? 'Nothing ticked = questions from all topics.'
                      : '${current.length} topic(s) selected.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: TopicPicker(
                      selected: current,
                      onChanged: (s) => setSheetState(() => current = s),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, current),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
