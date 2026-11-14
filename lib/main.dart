/// App entry point: starts the alarm backend and wires up the providers.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/alarm_backend.dart';
import 'services/alarm_provider.dart';
import 'services/bank_provider.dart';
import 'services/theme_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = AlarmBackend.forPlatform();
  try {
    await backend.init();
  } catch (e) {
    debugPrint('Alarm backend failed to start: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => BankProvider()),
        ChangeNotifierProvider(create: (_) => AlarmProvider(backend: backend)),
      ],
      child: const QuizAlarmApp(),
    ),
  );
}

class QuizAlarmApp extends StatelessWidget {
  const QuizAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'BrainWake Alarm',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Makes every standard time widget follow the 12/24 hour setting.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: settings.use24Hour),
        child: child!,
      ),
      home: const HomeScreen(),
    );
  }
}
