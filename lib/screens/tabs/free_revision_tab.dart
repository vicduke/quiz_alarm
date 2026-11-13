import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../services/question_service.dart';

class FreeRevisionTab extends StatefulWidget {
  const FreeRevisionTab({super.key});
  @override
  State<FreeRevisionTab> createState() => _FreeRevisionTabState();
}

class _FreeRevisionTabState extends State<FreeRevisionTab> {
  bool _isRevising = false;
  Question? _currentQ;
  final _saqCtrl = TextEditingController();
  String? _feedback;

  void _startRevision() async {
    setState(() {
      _isRevising = true;
      _currentQ = null;
      _feedback = null;
    });
    _currentQ = await QuestionService.getNextQuestion([
      'Pharmacology',
    ]); // Demo fixed topic
    setState(() {});
  }

  void _submit(String answer) async {
    if (_currentQ == null) return;
    final isCorrect = await QuestionService.gradeAnswer(_currentQ!, answer);
    setState(() {
      _feedback = isCorrect
          ? 'Correct!'
          : 'Incorrect. Expected: ${_currentQ!.correctAnswer}';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRevising) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _startRevision,
          icon: const Icon(Icons.school),
          label: const Text('Start Pharmacology Revision'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(24),
            textStyle: const TextStyle(fontSize: 20),
          ),
        ),
      );
    }

    if (_currentQ == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Topic: ${_currentQ!.topic}',
            style: const TextStyle(
              color: Colors.amberAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _currentQ!.questionText,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (_currentQ!.type == QuestionType.mcq)
            ..._currentQ!.options.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ElevatedButton(
                  onPressed: () => _submit(o),
                  child: Text(o),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _saqCtrl,
              decoration: const InputDecoration(hintText: 'Answer...'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _submit(_saqCtrl.text),
              child: const Text('Submit'),
            ),
          ],
          if (_feedback != null) ...[
            const SizedBox(height: 24),
            Text(
              _feedback!,
              style: TextStyle(
                fontSize: 18,
                color: _feedback!.contains('Correct')
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _startRevision,
              child: const Text('Next Question'),
            ),
          ],
        ],
      ),
    );
  }
}
