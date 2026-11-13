/// Keeps the list of units, topics and progress in memory for the screens,
/// and reloads it whenever the question bank changes.
library;

import 'package:material_ui/material_ui.dart';

import '../data/question_repository.dart';
import '../models/models.dart';
import 'question_service.dart';

class BankProvider extends ChangeNotifier {
  List<StudyUnit> units = [];
  List<Topic> topics = [];
  Map<String, TopicStats> stats = {};
  bool isLoading = true;
  String? error;

  BankProvider() {
    QuestionService.changes.addListener(reload);
    reload();
  }

  Future<void> reload() async {
    try {
      final u = await QuestionRepository.getUnits();
      final t = await QuestionRepository.getTopics();
      final s = await QuestionRepository.getStats();
      units = u;
      topics = t;
      stats = s;
      error = null;
    } catch (e) {
      error = 'The question bank could not be opened: $e';
    }
    isLoading = false;
    notifyListeners();
  }

  List<Topic> topicsOf(String unitId) =>
      topics.where((t) => t.unitId == unitId).toList();

  TopicStats statsOf(String topicId) => stats[topicId] ?? const TopicStats();

  /// Short label for a stored selection, e.g. "Pharmacology".
  String describe(Iterable<String> selectors) =>
      QuestionRepository.describeIn(selectors, units, topics);

  /// Topic ids a stored selection stands for. Empty selection = empty set
  /// here (the caller shows that as "All topics").
  Set<String> selectedIds(Iterable<String> selectors) =>
      selectors.where((s) => s.trim().isNotEmpty).isEmpty
      ? <String>{}
      : QuestionRepository.resolveIn(selectors, units, topics).toSet();

  @override
  void dispose() {
    QuestionService.changes.removeListener(reload);
    super.dispose();
  }
}
