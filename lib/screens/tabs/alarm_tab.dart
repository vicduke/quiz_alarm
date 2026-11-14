/// Alarms tab: a hero card with the clock and the next alarm, then the
/// list of alarms.
library;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/alarm_provider.dart';
import '../../services/bank_provider.dart';
import '../../services/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/clock_display.dart';
import '../alarm_ring_screen.dart';
import '../edit_alarm_screen.dart';

class AlarmTab extends StatelessWidget {
  const AlarmTab({super.key});

  String _greeting(int hour) {
    if (hour < 5) return 'Still up?';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  /// When the soonest enabled alarm will ring, and which one it is.
  (AlarmItem, DateTime)? _next(AlarmProvider provider) {
    final now = DateTime.now();
    (AlarmItem, DateTime)? best;
    for (final a in provider.alarms.where((a) => a.isEnabled)) {
      // A registered time also covers a running snooze.
      final registered = provider.backend.scheduledTime(a.id);
      final when = (registered != null && registered.isAfter(now))
          ? registered
          : calculateNextTrigger(a.time, a.activeDays, now);
      if (best == null || when.isBefore(best.$2)) best = (a, when);
    }
    return best;
  }

  void _openEditor(BuildContext context, [AlarmItem? alarm]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditAlarmScreen(existingAlarm: alarm),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankProvider>();
    final use24 = context.watch<ThemeProvider>().use24Hour;
    final theme = Theme.of(context);

    return Consumer<AlarmProvider>(
      builder: (context, provider, child) {
        final now = DateTime.now();
        final next = _next(provider);

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 170),
              children: [
                HeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _greeting(now.hour),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            DateFormat('EEE d MMM').format(now),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ClockDisplay(),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              next == null
                                  ? Icons.notifications_off_rounded
                                  : Icons.notifications_active_rounded,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                next == null
                                    ? 'No alarm is switched on'
                                    : 'Next alarm '
                                          '${describeTimeUntil(next.$2, now)} '
                                          '(${formatClock(next.$2, use24Hour: use24)})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your alarms',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Test the quiz'),
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
                  ],
                ),
                if (provider.backend.isSimulated)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Simulator: alarms ring inside the app. Tap the bell '
                      'on an alarm to ring it in 3 s.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 4),
                if (provider.alarms.isEmpty)
                  _EmptyAlarms(onAdd: () => _openEditor(context)),
                for (final a in provider.alarms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AlarmCard(
                      alarm: a,
                      topics: bank.describe(a.topics),
                      use24Hour: use24,
                      simulated: provider.backend.isSimulated,
                      onTap: () => _openEditor(context, a),
                      onToggle: (v) {
                        a.isEnabled = v;
                        provider.updateAlarm(a);
                      },
                      onRingNow: () {
                        provider.ringSoon(a);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 2),
                            content: Text('Ringing in 3 s...'),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
            if (provider.alarms.isNotEmpty)
              Positioned(
                right: 16,
                bottom: 104,
                child: GradientButton(
                  icon: Icons.add_rounded,
                  label: 'Add Alarm',
                  onPressed: () => _openEditor(context),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyAlarms extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyAlarms({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.dawn,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.alarm_add_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text('No alarms yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Set one and wake up by answering questions.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GradientButton(
              icon: Icons.add_rounded,
              label: 'Add Alarm',
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  final AlarmItem alarm;
  final String topics;
  final bool use24Hour;
  final bool simulated;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRingNow;

  const _AlarmCard({
    required this.alarm,
    required this.topics,
    required this.use24Hour,
    required this.simulated,
    required this.onTap,
    required this.onToggle,
    required this.onRingNow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = alarm;
    final on = a.isEnabled;
    final ink = on ? scheme.onSurface : scheme.onSurfaceVariant;
    final t = DateTime(2020, 1, 1, a.time.hour, a.time.minute);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Opacity(
      opacity: on ? 1 : 0.6,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            DateFormat(use24Hour ? 'HH:mm' : 'h:mm').format(t),
                            style: TextStyle(
                              fontFamily: AppTheme.display,
                              fontSize: 42,
                              height: 1.05,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                              color: ink,
                            ),
                          ),
                          if (!use24Hour) ...[
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('a').format(t),
                              style: TextStyle(
                                fontFamily: AppTheme.display,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (simulated)
                      IconButton(
                        tooltip: 'Ring in 3 seconds',
                        icon: const Icon(Icons.notifications_active_outlined),
                        onPressed: onRingNow,
                      ),
                    Switch(value: on, onChanged: onToggle),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (a.activeDays.isEmpty)
                      const Pill('Once', icon: Icons.looks_one_rounded)
                    else
                      for (var d = 1; d <= 7; d++)
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: a.activeDays.contains(d)
                                ? scheme.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: a.activeDays.contains(d)
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            letters[d - 1],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: a.activeDays.contains(d)
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    const Spacer(),
                    Pill(
                      AlarmItem.difficultyName(a.requiredStreak),
                      icon: Icons.bolt_rounded,
                      color: scheme.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        topics,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
