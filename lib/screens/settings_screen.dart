import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/alarm_provider.dart';
import '../services/question_service.dart';
import '../services/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    QuestionService.getApiKey().then((k) {
      if (mounted) _keyController.text = k ?? '';
    });
    QuestionService.getModel().then((m) {
      if (mounted) _modelController.text = m;
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await QuestionService.setApiKey(_keyController.text);
    await QuestionService.setModel(_modelController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved Settings')));
    // Top up the offline bank in the background with the new key/model.
    Provider.of<AlarmProvider>(context, listen: false).refillQuestionBank();
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    await QuestionService.setApiKey(_keyController.text);
    await QuestionService.setModel(_modelController.text);
    final error = await QuestionService.testApiKey();
    if (!mounted) return;
    setState(() => _testing = false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(error == null ? 'Connection works' : 'Connection failed'),
        content: Text(
          error ?? 'The key and model are valid. Questions can be generated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
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
            'Gemini API key (generates new questions ahead of time)',
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
          const Text('Model', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: QuestionService.defaultModel,
              helperText:
                  'If a test fails with "not found", try a newer Gemini Flash model name.',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _testing ? null : _test,
            child: Text(_testing ? 'Testing...' : 'Test connection'),
          ),
        ],
      ),
    );
  }
}
