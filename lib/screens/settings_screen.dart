import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/theme_provider.dart';
import '../services/question_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    QuestionService.getApiKey().then((k) => _keyController.text = k ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Dark Theme'),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              value: isDark,
              onChanged: (v) => themeProvider.toggleTheme(v),
            ),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Gemini API Key (Required for on-the-fly generation)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter API Key',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                QuestionService.setApiKey(_keyController.text);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Saved Settings')));
              },
              child: const Text('Save API Key'),
            ),
          ],
        ),
      ),
    );
  }
}
