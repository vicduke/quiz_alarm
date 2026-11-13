/// Alarms tab: clock, the list of alarms and the "Add alarm" button.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/alarm_provider.dart';
import '../../services/bank_provider.dart';
import '../../widgets/clock_display.dart';
import '../edit_alarm_screen.dart';
import '../alarm_ring_screen.dart';

class AlarmTab extends StatelessWidget {
  const AlarmTab({super.key});

  String _days(AlarmItem a) {
    if (a.activeDays.isEmpty) return 'Once';
    if (a.activeDays.length == 7) return 'Every day';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [...a.activeDays]..sort();
    return sorted.map((d) => names[d - 1]).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Consumer<AlarmProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const ClockDisplay(),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Test Alarm Screen'),
                    onPressed: () {
                      // A preview: it can be closed and does not touch
                      // any real alarm.
                      final sample = provider.alarms.isNotEmpty
                          ? provider.alarms.first
                          : AlarmItem(
                              id: 1,
                              time: TimeOfDay.now(),
                              topics: const [],
                            );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AlarmRingScreen(alarm: sample, preview: true),
                        ),
                      );
                    },
                  ),
                  if (provider.backend.isSimulated)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Simulator: alarms ring inside the app. '
                        'Tap the bell on an alarm to ring it in 3 s.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: provider.alarms.isEmpty
                  ? const Center(child: Text('No alarms set.'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 6),
                      itemCount: provider.alarms.length,
                      itemBuilder: (ctx, i) {
                        final a = provider.alarms[i];
                        final faded = scheme.onSurface.withValues(alpha: 0.45);
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EditAlarmScreen(existingAlarm: a),
                                  fullscreenDialog: true,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          a.time.format(context),
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: a.isEnabled
                                                ? scheme.onSurface
                                                : faded,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${a.label} - ${_days(a)} - '
                                          '${AlarmItem.difficultyName(a.requiredStreak)}',
                                          style: TextStyle(
                                            color: a.isEnabled
                                                ? scheme.onSurfaceVariant
                                                : faded,
                                          ),
                                        ),
                                        Text(
                                          bank.describe(a.topics),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: a.isEnabled
                                                ? scheme.secondary
                                                : faded,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (provider.backend.isSimulated)
                                    IconButton(
                                      tooltip: 'Ring in 3 seconds',
                                      icon: const Icon(
                                        Icons.notifications_active_outlined,
                                      ),
                                      onPressed: () {
                                        provider.ringSoon(a);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            duration: Duration(seconds: 2),
                                            content: Text('Ringing in 3 s...'),
                                          ),
                                        );
                                      },
                                    ),
                                  Switch(
                                    value: a.isEnabled,
                                    onChanged: (v) {
                                      a.isEnabled = v;
                                      provider.updateAlarm(a);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditAlarmScreen(),
                      fullscreenDialog: true,
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Alarm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
