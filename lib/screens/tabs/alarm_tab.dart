import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/alarm_provider.dart';
import '../../widgets/clock_display.dart';
import '../edit_alarm_screen.dart';
import '../alarm_ring_screen.dart';

class AlarmTab extends StatelessWidget {
  const AlarmTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const ClockDisplay(),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Test Alarm Screen'),
                    onPressed: () {
                      if (provider.alarms.isNotEmpty) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AlarmRingScreen(alarm: provider.alarms.first),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please add an alarm to test!'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: provider.alarms.isEmpty
                  ? const Center(child: Text('No alarms set.'))
                  : ListView.builder(
                      itemCount: provider.alarms.length,
                      itemBuilder: (ctx, i) {
                        final a = provider.alarms[i];
                        return Card(
                          color: const Color(0xFF1C1C1E),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
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
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.time.format(context),
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: a.isEnabled
                                              ? Colors.white
                                              : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${a.label} • ${a.topics.join(", ")}',
                                        style: TextStyle(
                                          color: a.isEnabled
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Switch(
                                    activeThumbColor: Colors.blueAccent,
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
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditAlarmScreen(),
                      fullscreenDialog:
                          true, // Slides up from bottom like native iOS/Android
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Alarm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
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
