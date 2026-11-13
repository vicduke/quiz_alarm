import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/question_service.dart';

class QuestionBankTab extends StatefulWidget {
  const QuestionBankTab({super.key});
  @override
  State<QuestionBankTab> createState() => _QuestionBankTabState();
}

class _QuestionBankTabState extends State<QuestionBankTab> {
  Map<String, List<Question>> _groupedQuestions = {};

  @override
  void initState() {
    super.initState();
    _loadBank();
  }

  Future<void> _loadBank() async {
    final list = await QuestionService.getOfflineBank();
    Map<String, List<Question>> grouped = {};
    for (var q in list) {
      grouped.putIfAbsent(q.topic, () => []).add(q);
    }
    setState(() => _groupedQuestions = grouped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _groupedQuestions.isEmpty
          ? const Center(child: Text('Bank is empty.'))
          : ListView(
              children: _groupedQuestions.entries.map((entry) {
                return ExpansionTile(
                  title: Text(
                    '${entry.key} (${entry.value.length} Questions)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: entry.value
                      .map(
                        (q) => ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              q.type == QuestionType.mcq ? 'MCQ' : 'SAQ',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          title: Text(q.questionText),
                          subtitle: Text('Ans: ${q.correctAnswer}'),
                        ),
                      )
                      .toList(),
                );
              }).toList(),
            ),
    );
  }
}
