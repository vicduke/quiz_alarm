/// Settings: theme, Gemini API key / model, and a visible status of the
/// AI question generation (so failures are no longer silent).
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/alarm_provider.dart';
import '../services/gemini_client.dart';
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
  bool _generating = false;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    GeminiClient.getApiKey().then((k) {
      if (mounted) _keyController.text = k ?? '';
    });
    GeminiClient.getModel().then((m) {
      if (mounted) _modelController.text = m;
    });
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await QuestionService.lastStatus();
    if (mounted) setState(() => _lastStatus = s);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _store() async {
    await GeminiClient.setApiKey(_keyController.text);
    await GeminiClient.setModel(_modelController.text);
  }

  void _dialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await _store();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved Settings')));
    // Top up the offline bank in the background with the new key/model.
    Provider.of<AlarmProvider>(
      context,
      listen: false,
    ).refillQuestionBank().then((_) => _loadStatus());
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    await _store();
    final error = await GeminiClient.testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    _dialog(
      error == null ? 'Connection works' : 'Connection failed',
      error ?? 'The key and model are valid. Questions can be generated.',
    );
  }

  /// Runs a top-up for every topic right now and shows exactly what
  /// happened, including the error if it fails.
  Future<void> _generateNow() async {
    setState(() => _generating = true);
    await _store();
    if (!await GeminiClient.hasApiKey()) {
      if (!mounted) return;
      setState(() => _generating = false);
      _dialog('API key needed', 'Enter your Gemini API key first.');
      return;
    }
    final result = await QuestionService.topUp(const [], targetUnseen: 1 << 30);
    await _loadStatus();
    if (!mounted) return;
    setState(() => _generating = false);
    if (result.error != null) {
      _dialog(
        'Generation failed',
        '${result.added > 0 ? 'Added ${result.added} question(s), then:\n\n' : ''}'
            '${result.error}',
      );
    } else {
      _dialog(
        'Questions added',
        'Added ${result.added} new question(s). They are in Question Banks, '
            'marked "AI generated".',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final small = Theme.of(context).textTheme.bodySmall;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark Theme'),
                  secondary: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  ),
                  value: isDark,
                  onChanged: (v) => themeProvider.toggleTheme(v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: const Text('24-hour clock'),
                  subtitle: Text(
                    themeProvider.use24Hour
                        ? 'Times show as 18:30'
                        : 'Times show as 6:30 PM',
                  ),
                  secondary: const Icon(Icons.schedule_rounded),
                  value: themeProvider.use24Hour,
                  onChanged: (v) => themeProvider.setUse24Hour(v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                const ListTile(
                  leading: Icon(Icons.volume_up_rounded),
                  title: Text('Alarm volume'),
                  subtitle: Text(
                    'Always the maximum. The phone volume is raised when an '
                    'alarm rings and put back when you dismiss it.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Gemini API key',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Used to write new questions ahead of time and for the AI tutor '
            'in Free Revision. Everything else works offline.',
            style: small,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(hintText: 'Enter API Key'),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          const Text('Model', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              hintText: GeminiClient.defaultModel,
              helperText: 'If a test fails with "not found", try a newer Gemini Flash model name.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _testing ? null : _test,
            child: Text(_testing ? 'Testing...' : 'Test connection'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'AI question generation',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'New questions are written automatically when the topics of your '
            'alarms have fewer than 5 unanswered questions left.',
            style: small,
          ),
          const SizedBox(height: 8),
          Text('Last run: ${_lastStatus ?? 'nothing generated yet'}'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _generating ? null : _generateNow,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _generating
                  ? 'Writing questions (up to 2 minutes)...'
                  : 'Generate questions now',
            ),
          ),
        ],
      ),
    );
  }
}
