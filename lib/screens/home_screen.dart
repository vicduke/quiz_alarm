/// The app shell: glowing background, header, the four tabs in a floating
/// navigation bar, and the hook that opens the quiz when an alarm rings.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alarm_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'alarm_ring_screen.dart';
import 'settings_screen.dart';
import 'tabs/alarm_tab.dart';
import 'tabs/free_revision_tab.dart';
import 'tabs/question_bank_tab.dart';
import 'tabs/reports_tab.dart';

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
    ReportsTab(),
  ];
  static const List<String> _titles = [
    'BrainWake',
    'Question banks',
    'Revision',
    'Reports',
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
            SnackBar(
              content: Text('Snoozed for ${alarm.snoozeMinutes} minutes.'),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Text(_titles[_currentIndex]);

    return Scaffold(
      extendBody: true,
      body: GlowBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontFamily: AppTheme.display,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                        // The app name wears the dawn gradient.
                        child: _currentIndex == 0
                            ? ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (r) =>
                                    AppColors.dawn.createShader(r),
                                child: title,
                              )
                            : DefaultTextStyle.merge(
                                style: TextStyle(color: scheme.onSurface),
                                child: title,
                              ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _tabs[_currentIndex]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.45 : 0.10,
                ),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.alarm_rounded),
                label: 'Alarms',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_stories_rounded),
                label: 'Banks',
              ),
              NavigationDestination(
                icon: Icon(Icons.style_rounded),
                label: 'Revision',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_rounded),
                label: 'Reports',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
