/// Free Revision tab: choose random or specific topics, then revise with
/// flash cards. With an API key the AI tutor explains each answer.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/bank_provider.dart';
import '../../services/gemini_client.dart';
import '../../widgets/topic_picker.dart';
import '../practice_screen.dart';
import '../settings_screen.dart';

class FreeRevisionTab extends StatefulWidget {
  const FreeRevisionTab({super.key});
  @override
  State<FreeRevisionTab> createState() => _FreeRevisionTabState();
}

class _FreeRevisionTabState extends State<FreeRevisionTab> {
  static const _topicsPref = 'revision_topics';
  static const _randomPref = 'revision_random';
  static const _aiPref = 'revision_ai_tutor';

  bool _random = true;
  Set<String> _topics = {};
  bool _aiTutor = true;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final hasKey = await GeminiClient.hasApiKey();
    if (!mounted) return;
    setState(() {
      _random = prefs.getBool(_randomPref) ?? true;
      _topics = (prefs.getStringList(_topicsPref) ?? const []).toSet();
      _aiTutor = prefs.getBool(_aiPref) ?? true;
      _hasKey = hasKey;
    });
  }

  Future<void> _remember() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_randomPref, _random);
    await prefs.setStringList(_topicsPref, _topics.toList());
    await prefs.setBool(_aiPref, _aiTutor);
  }

  Future<void> _start(BankProvider bank) async {
    // Ignore remembered topics that no longer exist.
    final known = bank.topics.map((t) => t.id).toSet();
    final picked = _topics.intersection(known).toList();
    await _remember();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          title: _random ? 'Random revision' : bank.describe(picked),
          selectors: _random ? const [] : picked,
          aiTutor: _aiTutor && _hasKey,
          mode: 'revision',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankProvider>();
    final theme = Theme.of(context);
    final known = bank.topics.map((t) => t.id).toSet();
    final picked = _topics.intersection(known);
    final canStart = _random || picked.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Flash-card revision', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Answer each card, then see the right answer and why. Questions '
          'you have not seen or got wrong come up first.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.shuffle),
              label: Text('Random topics'),
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.checklist),
              label: Text('Choose topics'),
            ),
          ],
          selected: {_random},
          onSelectionChanged: (s) => setState(() => _random = s.first),
        ),
        const SizedBox(height: 16),
        if (!_random)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TopicPicker(
                selected: picked,
                onChanged: (s) => setState(() => _topics = s),
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome),
                title: const Text('AI tutor'),
                subtitle: Text(
                  _hasKey
                      ? 'Explains where your answer went wrong. Needs '
                            'internet; saved explanations are used offline.'
                      : 'Needs a Gemini API key. Without it you still get '
                            'the saved explanations.',
                ),
                value: _aiTutor && _hasKey,
                onChanged: _hasKey ? (v) => setState(() => _aiTutor = v) : null,
              ),
              if (!_hasKey)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 56, bottom: 8),
                    child: TextButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                        _restore();
                      },
                      child: const Text('Add a key in Settings'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: canStart ? () => _start(bank) : null,
          icon: const Icon(Icons.school),
          label: Text(canStart ? 'Start revision' : 'Pick at least one topic'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
      ],
    );
  }
}
