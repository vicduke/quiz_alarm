/// The three tabs, plus the hook that opens the ring screen when an alarm
/// goes off.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alarm_provider.dart';
import 'alarm_ring_screen.dart';
import 'settings_screen.dart';
import 'tabs/alarm_tab.dart';
import 'tabs/free_revision_tab.dart';
import 'tabs/question_bank_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<Widget> _tabs = const [
    AlarmTab(),
    QuestionBankTab(),
    FreeRevisionTab(),
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AlarmProvider>(context, listen: false);
      // The simulator has no OS permissions to ask for.
      if (!provider.backend.isSimulated) _requestPermissions();

      provider.onAlarmTriggered = (alarm) async {
        if (!mounted) {
          provider.ringScreenClosed();
          return;
        }
        final result = await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlarmRingScreen(alarm: alarm)),
        );
        if (result == 'snooze' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mercy Snooze active for 5 minutes.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        provider.ringScreenClosed();
      };
    });
  }

  Future<void> _requestPermissions() async {
    try {
      // 1. Request Notification Permission (Required for Android 13+)
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // 2. Request Exact Alarm Permission (Required for Android 12+)
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }

      // 3. Battery optimization can delay or kill alarms on many phones.
      // Ask once only, so we don't nag on every launch.
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('asked_battery_opt') ?? false)) {
        await prefs.setBool('asked_battery_opt', true);
        if (!await Permission.ignoreBatteryOptimizations.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BrainWake',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Alarms'),
          NavigationDestination(
            icon: Icon(Icons.library_books),
            label: 'Question Banks',
          ),
          NavigationDestination(
            icon: Icon(Icons.school),
            label: 'Free Revision',
          ),
        ],
      ),
    );
  }
}
