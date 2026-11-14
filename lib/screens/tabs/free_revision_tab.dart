/// Free Revision tab: choose random or specific topics, then revise with
/// flash cards. With an API key the AI tutor explains each answer.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/bank_provider.dart';
import '../../services/gemini_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      children: [
        HeroCard(
          gradient: AppColors.night,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flash cards',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Answer each card, then see the right answer and why. '
                      'Questions you have not seen or got wrong come first.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.style_rounded, size: 32),
              ),
            ],
          ),
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
        GradientButton(
          onPressed: canStart ? () => _start(bank) : null,
          icon: Icons.play_arrow_rounded,
          label: canStart ? 'Start revision' : 'Pick at least one topic',
        ),
      ],
    );
  }
}
