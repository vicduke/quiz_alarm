import 'package:alarm/alarm.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/alarm_provider.dart';
import 'services/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AlarmProvider()),
      ],
      child: const QuizAlarmApp(),
    ),
  );
}

class QuizAlarmApp extends StatelessWidget {
  const QuizAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'BrainWake Alarm',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.deepPurple,
        colorScheme: const ColorScheme.light(
          primary: Colors.deepPurple,
          secondary: Colors.amber,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurpleAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.amberAccent,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
