/// All reads and writes of units, topics, questions and attempts.
///
/// Question banks ship as JSON files in `assets/question_banks/`. Each file
/// is one unit with its topics and questions; it is copied into the database
/// the first time the app runs and again whenever its `version` goes up.
/// Questions keep their ids across re-imports, so progress is never lost.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'app_database.dart';

class QuestionRepository {
  static const String seedFolder = 'assets/question_banks/';
  static const String customUnitId = 'custom';
  static const String _legacyBankPref = 'offline_question_bank';

  static Future<void>? _ready;

  /// Opens the database and imports bundled / legacy data once.
  static Future<void> ensureReady() => _ready ??= _init();

  @visibleForTesting
  static void resetForTest() => _ready = null;

  static Future<Database> get _db => AppDatabase.instance;

  static Future<void> _init() async {
    await _db;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files =
          manifest
              .listAssets()
              .where((a) => a.startsWith(seedFolder) && a.endsWith('.json'))
              .toList()
            ..sort();
      for (var i = 0; i < files.length; i++) {
        try {
          final data = jsonDecode(await rootBundle.loadString(files[i]));
          await importUnit(data as Map<String, dynamic>, sortOrder: i);
        } catch (e) {
          debugPrint('Could not import ${files[i]}: $e');
        }
      }
    } catch (e) {
      debugPrint('No bundled question banks found: $e');
    }
    await _importLegacyBank();
  }

  // ------------------------------------------------------------- importing

  static String textKey(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String slug(String text) {
    final s = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'topic' : s;
  }

  /// Copies one unit file into the database. Does nothing when this
  /// version of the file was already imported (unless [force]).
  static Future<void> importUnit(
    Map<String, dynamic> data, {
    int sortOrder = 0,
    bool force = false,
  }) async {
    final db = await _db;
    final unit = data['unit'] as Map<String, dynamic>;
    final unitId = unit['id'] as String;
    final version = '${data['version'] ?? 1}';
    final metaKey = 'seed:$unitId';

    final seen = await db.query('meta', where: 'key = ?', whereArgs: [metaKey]);
    if (!force && seen.isNotEmpty && seen.first['value'] == version) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT INTO units(id, name, description, sort_order) VALUES(?,?,?,?) '
        'ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
        'description = excluded.description, sort_order = excluded.sort_order',
        [unitId, unit['name'], unit['description'] ?? '', sortOrder],
      );

      final keepTopics = <String>[];
      final keepQuestions = <String>[];
      final topics = (data['topics'] as List).cast<Map<String, dynamic>>();
      for (var t = 0; t < topics.length; t++) {
        final topicId = topics[t]['id'] as String;
        keepTopics.add(topicId);
        await txn.rawInsert(
          'INSERT INTO topics(id, unit_id, name, sort_order, is_custom) '
          'VALUES(?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET '
          'unit_id = excluded.unit_id, name = excluded.name, '
          'sort_order = excluded.sort_order',
          [topicId, unitId, topics[t]['name'], t],
        );

        final questions = ((topics[t]['questions'] ?? const []) as List)
            .cast<Map<String, dynamic>>();
        for (final q in questions) {
          final id = q['id'] as String;
          final text = (q['text'] as String).trim();
          final key = textKey(text);
          keepQuestions.add(id);
          // A generated copy of the same question gives way to the curated one.
          await txn.delete(
            'questions',
            where: 'topic_id = ? AND text_key = ? AND id != ?',
            whereArgs: [topicId, key, id],
          );
          await txn.rawInsert(
            'INSERT INTO questions(id, topic_id, type, text, text_key, options, '
            'answer, alt_answers, explanation, source, created_at) '
            "VALUES(?,?,?,?,?,?,?,?,?,'seed',?) ON CONFLICT(id) DO UPDATE SET "
            'topic_id = excluded.topic_id, type = excluded.type, '
            'text = excluded.text, text_key = excluded.text_key, '
            'options = excluded.options, answer = excluded.answer, '
            'alt_answers = excluded.alt_answers, explanation = excluded.explanation',
            [
              id,
              topicId,
              q['type'] == 'mcq' ? 'mcq' : 'saq',
              text,
              key,
              jsonEncode(q['options'] ?? const []),
              (q['answer'] as String).trim(),
              jsonEncode(q['alt_answers'] ?? const []),
              (q['explanation'] ?? '') as String,
              now,
            ],
          );
        }
      }

      // Drop curated questions/topics that were removed from the file.
      // Generated questions and topics that still hold some are kept.
      final qMarks = List.filled(keepQuestions.length, '?').join(',');
      await txn.rawDelete(
        "DELETE FROM questions WHERE source = 'seed' "
        'AND topic_id IN (SELECT id FROM topics WHERE unit_id = ?) '
        '${keepQuestions.isEmpty ? '' : 'AND id NOT IN ($qMarks)'}',
        [unitId, ...keepQuestions],
      );
      final tMarks = List.filled(keepTopics.length, '?').join(',');
      await txn.rawDelete(
        'DELETE FROM topics WHERE unit_id = ? AND is_custom = 0 '
        '${keepTopics.isEmpty ? '' : 'AND id NOT IN ($tMarks) '}'
        'AND id NOT IN (SELECT DISTINCT topic_id FROM questions)',
        [unitId, ...keepTopics],
      );

      await txn.insert('meta', {
        'key': metaKey,
        'value': version,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Moves AI questions saved by app versions that kept the bank in
  /// SharedPreferences into the database, then removes the old copy.
  static Future<void> _importLegacyBank() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyBankPref);
      if (raw == null) return;
      for (final e in jsonDecode(raw) as List) {
        try {
          final m = e as Map<String, dynamic>;
          final id = '${m['id'] ?? ''}';
          if (!id.startsWith('ai_')) continue; // old built-in demo questions
          final topicName = '${m['topic'] ?? 'General'}';
          final topic =
              await findTopicByName(topicName) ??
              await addCustomTopic(topicName);
          await addQuestion(
            Question(
              id: id,
              topicId: topic.id,
              topic: topic.name,
              type: m['type'] == 'mcq' ? QuestionType.mcq : QuestionType.saq,
              questionText: '${m['questionText']}',
              options: List<String>.from(m['options'] ?? const []),
              correctAnswer: '${m['correctAnswer']}',
              source: 'ai',
            ),
          );
        } catch (err) {
          debugPrint('Skipping unreadable saved question: $err');
        }
      }
      await prefs.remove(_legacyBankPref);
      await prefs.remove('asked_question_ids');
    } catch (e) {
      debugPrint('Old question bank could not be imported: $e');
    }
  }

  // ---------------------------------------------------------------- topics

  static Future<List<StudyUnit>> getUnits() async {
    await ensureReady();
    final rows = await (await _db).query('units', orderBy: 'sort_order, name');
    return rows
        .map(
          (r) => StudyUnit(
            id: r['id'] as String,
            name: r['name'] as String,
            description: (r['description'] ?? '') as String,
          ),
        )
        .toList();
  }

  static Topic _topicFromRow(Map<String, Object?> r) => Topic(
    id: r['id'] as String,
    unitId: r['unit_id'] as String,
    name: r['name'] as String,
    isCustom: r['is_custom'] == 1,
  );

  static Future<List<Topic>> getTopics() async {
    await ensureReady();
    final rows = await (await _db).rawQuery(
      'SELECT t.* FROM topics t JOIN units u ON u.id = t.unit_id '
      'ORDER BY u.sort_order, u.name, t.sort_order, t.name',
    );
    return rows.map(_topicFromRow).toList();
  }

  static Future<Topic?> findTopicByName(String name) async {
    final rows = await (await _db).query(
      'topics',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : _topicFromRow(rows.first);
  }

  /// Creates a topic of the user's own (under [unitId], or under
  /// "My topics"). Returns the existing topic if the name is already used.
  static Future<Topic> addCustomTopic(String name, {String? unitId}) async {
    final db = await _db;
    final clean = name.trim();
    final unit = unitId ?? customUnitId;
    final existing = await db.query(
      'topics',
      where: 'unit_id = ? AND LOWER(name) = ?',
      whereArgs: [unit, clean.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return _topicFromRow(existing.first);

    if (unit == customUnitId) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO units(id, name, description, sort_order) '
        "VALUES(?, 'My topics', 'Topics you added yourself', 1000)",
        [customUnitId],
      );
    }
    var id = '$unit-${slug(clean)}';
    var n = 2;
    while ((await db.query(
      'topics',
      where: 'id = ?',
      whereArgs: [id],
    )).isNotEmpty) {
      id = '$unit-${slug(clean)}-${n++}';
    }
    await db.insert('topics', {
      'id': id,
      'unit_id': unit,
      'name': clean,
      'sort_order': 1000,
      'is_custom': 1,
    });
    return Topic(id: id, unitId: unit, name: clean, isCustom: true);
  }

  /// Deletes a user-made topic with its questions.
  static Future<void> deleteCustomTopic(String topicId) async {
    await (await _db).delete(
      'topics',
      where: 'id = ? AND is_custom = 1',
      whereArgs: [topicId],
    );
  }

  /// Turns what an alarm or a session stores (topic ids, unit ids, or names
  /// from older versions) into topic ids. Empty or unknown input means
  /// every topic.
  static List<String> resolveIn(
    Iterable<String> selectors,
    List<StudyUnit> units,
    List<Topic> topics,
  ) {
    final ids = <String>{};
    for (final raw in selectors) {
      final s = raw.trim().toLowerCase();
      if (s.isEmpty) continue;
      final unitIds = units
          .where((u) => u.id.toLowerCase() == s || u.name.toLowerCase() == s)
          .map((u) => u.id)
          .toSet();
      for (final t in topics) {
        if (t.id.toLowerCase() == s ||
            t.name.toLowerCase() == s ||
            unitIds.contains(t.unitId)) {
          ids.add(t.id);
        }
      }
    }
    if (ids.isEmpty) return topics.map((t) => t.id).toList();
    return ids.toList();
  }

  static Future<List<String>> resolveTopicIds(
    Iterable<String> selectors,
  ) async => resolveIn(selectors, await getUnits(), await getTopics());

  /// A short human label for what [selectors] cover, e.g.
  /// "Pharmacology" or "Antimicrobials, CNS drugs".
  static String describeIn(
    Iterable<String> selectors,
    List<StudyUnit> units,
    List<Topic> topics,
  ) {
    final wanted = selectors.where((s) => s.trim().isNotEmpty).toList();
    if (wanted.isEmpty || topics.isEmpty) return 'All topics';
    final ids = resolveIn(wanted, units, topics).toSet();
    if (ids.length == topics.length) return 'All topics';

    final parts = <String>[];
    for (final u in units) {
      final inUnit = topics.where((t) => t.unitId == u.id).toList();
      final picked = inUnit.where((t) => ids.contains(t.id)).toList();
      if (picked.isEmpty) continue;
      if (picked.length == inUnit.length) {
        parts.add(u.name);
      } else {
        parts.addAll(picked.map((t) => t.name));
      }
    }
    if (parts.length > 3) {
      return '${parts.take(2).join(', ')} +${parts.length - 2} more';
    }
    return parts.join(', ');
  }

  static Future<String> describeSelection(Iterable<String> selectors) async =>
      describeIn(selectors, await getUnits(), await getTopics());

  // ------------------------------------------------------------- questions

  static const String _questionSelect =
      'SELECT q.*, t.name AS topic_name FROM questions q '
      'JOIN topics t ON t.id = q.topic_id';

  static Future<List<Question>> getQuestions(String topicId) async {
    await ensureReady();
    final rows = await (await _db).rawQuery(
      '$_questionSelect WHERE q.topic_id = ? ORDER BY q.created_at, q.id',
      [topicId],
    );
    return rows.map(Question.fromRow).toList();
  }

  /// Stores [q] unless its topic already has a question with the same text.
  /// Returns true if it was added.
  static Future<bool> addQuestion(Question q) async {
    final db = await _db;
    await db.insert('questions', {
      'id': q.id,
      'topic_id': q.topicId,
      'type': q.type == QuestionType.mcq ? 'mcq' : 'saq',
      'text': q.questionText.trim(),
      'text_key': textKey(q.questionText),
      'options': jsonEncode(q.options),
      'answer': q.correctAnswer.trim(),
      'alt_answers': jsonEncode(q.altAnswers),
      'explanation': q.explanation.trim(),
      'source': q.source,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final stored = await db.query(
      'questions',
      where: 'id = ?',
      whereArgs: [q.id],
    );
    return stored.isNotEmpty;
  }

  static Future<void> setExplanation(String questionId, String text) async {
    await (await _db).update(
      'questions',
      {'explanation': text.trim()},
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  static Future<void> deleteQuestion(String questionId) async {
    await (await _db).delete(
      'questions',
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  static Future<void> recordAttempt(
    String questionId, {
    required bool correct,
    required String mode,
    int? sessionId,
    String userAnswer = '',
    Duration? timeTaken,
  }) async {
    try {
      await (await _db).insert('attempts', {
        'question_id': questionId,
        'mode': mode,
        'correct': correct ? 1 : 0,
        'answered_at': DateTime.now().millisecondsSinceEpoch,
        'session_id': sessionId,
        'user_answer': userAnswer.trim(),
        'duration_ms': timeTaken?.inMilliseconds,
      });
    } catch (e) {
      debugPrint('Could not record the answer: $e');
    }
  }

  /// Per-topic totals, keyed by topic id.
  static Future<Map<String, TopicStats>> getStats() async {
    await ensureReady();
    final rows = await (await _db).rawQuery('''
      SELECT q.topic_id AS topic_id,
             COUNT(*) AS total,
             SUM(CASE WHEN la.correct IS NOT NULL THEN 1 ELSE 0 END) AS seen,
             SUM(CASE WHEN la.correct = 1 THEN 1 ELSE 0 END) AS mastered
      FROM questions q
      LEFT JOIN attempts la ON la.id =
        (SELECT MAX(a.id) FROM attempts a WHERE a.question_id = q.id)
      GROUP BY q.topic_id''');
    return {
      for (final r in rows)
        r['topic_id'] as String: TopicStats(
          total: (r['total'] as int?) ?? 0,
          seen: (r['seen'] as int?) ?? 0,
          mastered: (r['mastered'] as int?) ?? 0,
        ),
    };
  }

  /// Picks the next question from [topicIds]. Order of preference:
  /// never answered, then last answered wrong, then answered longest ago.
  /// Questions in [exclude] (already shown this session) are avoided
  /// while anything else is left. Returns null only if there are no
  /// questions at all.
  static Future<Question?> pickNext(
    List<String> topicIds, {
    Set<String> exclude = const {},
    Random? rng,
  }) async {
    await ensureReady();
    final db = await _db;
    Future<List<Map<String, Object?>>> load(List<String> ids) {
      final marks = List.filled(ids.length, '?').join(',');
      return db.rawQuery(
        'SELECT q.*, t.name AS topic_name, la.correct AS last_correct, '
        'la.answered_at AS last_at FROM questions q '
        'JOIN topics t ON t.id = q.topic_id '
        'LEFT JOIN attempts la ON la.id = '
        '(SELECT MAX(a.id) FROM attempts a WHERE a.question_id = q.id) '
        '${ids.isEmpty ? '' : 'WHERE q.topic_id IN ($marks)'}',
        ids,
      );
    }

    var rows = await load(topicIds);
    if (rows.isEmpty && topicIds.isNotEmpty) rows = await load(const []);
    if (rows.isEmpty) return null;

    var pool = rows.where((r) => !exclude.contains(r['id'])).toList();
    // (query results are read-only, hence the copy before sorting below)
    if (pool.isEmpty) pool = List.of(rows);

    final random = rng ?? Random();
    final unseen = pool.where((r) => r['last_at'] == null).toList();
    if (unseen.isNotEmpty) {
      return Question.fromRow(unseen[random.nextInt(unseen.length)])
          .shuffled(random);
    }
    int at(Map<String, Object?> r) => (r['last_at'] as int?) ?? 0;
    final wrong = pool.where((r) => r['last_correct'] == 0).toList()
      ..sort((a, b) => at(a).compareTo(at(b)));
    final tier = wrong.isNotEmpty
        ? wrong
        : (pool..sort((a, b) => at(a).compareTo(at(b))));
    final oldest = tier.take(min(5, tier.length)).toList();
    return Question.fromRow(oldest[random.nextInt(oldest.length)])
        .shuffled(random);
  }

  // -------------------------------------------------- sessions and reports

  /// Starts a session ('alarm', 'revision' or 'bank') and returns its id,
  /// or null if it could not be saved (the quiz must go on regardless).
  static Future<int?> startSession(
    String kind,
    String title, {
    int? alarmId,
    int? requiredStreak,
  }) async {
    try {
      await ensureReady();
      return await (await _db).insert('sessions', {
        'kind': kind,
        'title': title,
        'alarm_id': alarmId,
        'required_streak': requiredStreak,
        'started_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Could not start a session: $e');
      return null;
    }
  }

  /// Closes a session. One in which nothing was answered is removed.
  static Future<void> endSession(int? id, String outcome) async {
    if (id == null) return;
    try {
      final db = await _db;
      final n = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM attempts WHERE session_id = ?',
          [id],
        ),
      );
      if ((n ?? 0) == 0 && outcome != 'dismissed' && outcome != 'snoozed') {
        await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
        return;
      }
      await db.update(
        'sessions',
        {'ended_at': DateTime.now().millisecondsSinceEpoch, 'outcome': outcome},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Could not close the session: $e');
    }
  }

  static DateTime _time(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms as int);

  /// Past sessions, newest first. [kind] filters to one kind.
  static Future<List<StudySession>> getSessions({
    String? kind,
    int limit = 100,
  }) async {
    await ensureReady();
    final rows = await (await _db).rawQuery(
      'SELECT s.*, COUNT(a.id) AS questions, '
      'COALESCE(SUM(a.correct), 0) AS correct_count '
      'FROM sessions s LEFT JOIN attempts a ON a.session_id = s.id '
      '${kind == null ? '' : 'WHERE s.kind = ? '}'
      'GROUP BY s.id ORDER BY s.started_at DESC LIMIT ?',
      [?kind, limit],
    );
    return rows
        .map(
          (r) => StudySession(
            id: r['id'] as int,
            kind: r['kind'] as String,
            title: r['title'] as String,
            startedAt: _time(r['started_at']),
            endedAt: r['ended_at'] == null ? null : _time(r['ended_at']),
            outcome: r['outcome'] as String?,
            requiredStreak: r['required_streak'] as int?,
            questions: (r['questions'] as int?) ?? 0,
            correct: (r['correct_count'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// Every question answered in a session, in order, with what the user
  /// answered. The question (and so its explanation) comes from the
  /// database, so this works offline.
  static Future<List<AttemptDetail>> getSessionAttempts(int sessionId) async {
    final rows = await (await _db).rawQuery(
      'SELECT q.*, t.name AS topic_name, a.user_answer AS a_user_answer, '
      'a.correct AS a_correct, a.duration_ms AS a_duration_ms, '
      'a.answered_at AS a_answered_at FROM attempts a '
      'JOIN questions q ON q.id = a.question_id '
      'JOIN topics t ON t.id = q.topic_id '
      'WHERE a.session_id = ? ORDER BY a.id',
      [sessionId],
    );
    return rows
        .map(
          (r) => AttemptDetail(
            question: Question.fromRow(r),
            userAnswer: (r['a_user_answer'] ?? '') as String,
            correct: r['a_correct'] == 1,
            answeredAt: _time(r['a_answered_at']),
            timeTaken: r['a_duration_ms'] == null
                ? null
                : Duration(milliseconds: r['a_duration_ms'] as int),
          ),
        )
        .toList();
  }

  /// Totals, the last [days] days and per-topic accuracy for the Reports
  /// tab. [now] is only passed by tests.
  static Future<ReportSummary> getReport({int days = 14, DateTime? now}) async {
    await ensureReady();
    final db = await _db;
    final today = now ?? DateTime.now();
    final firstDay = DateTime(today.year, today.month, today.day - (days - 1));

    final totals = (await db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(correct), 0) AS c FROM attempts',
    )).first;

    final recent = await db.rawQuery(
      'SELECT answered_at, correct FROM attempts WHERE answered_at >= ?',
      [firstDay.millisecondsSinceEpoch],
    );
    final answered = List<int>.filled(days, 0);
    final correct = List<int>.filled(days, 0);
    for (final r in recent) {
      final t = _time(r['answered_at']);
      final i = DateTime(t.year, t.month, t.day).difference(firstDay).inHours;
      final index = (i / 24).round();
      if (index < 0 || index >= days) continue;
      answered[index]++;
      if (r['correct'] == 1) correct[index]++;
    }

    final topicRows = await db.rawQuery(
      'SELECT t.name AS name, COUNT(*) AS n, SUM(a.correct) AS c '
      'FROM attempts a JOIN questions q ON q.id = a.question_id '
      'JOIN topics t ON t.id = q.topic_id GROUP BY t.id',
    );
    final topics =
        topicRows
            .map(
              (r) => TopicAccuracy(
                r['name'] as String,
                (r['n'] as int?) ?? 0,
                (r['c'] as int?) ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => a.accuracy.compareTo(b.accuracy));

    final wake = (await db.rawQuery(
      "SELECT COUNT(*) AS n, AVG(ended_at - started_at) AS ms, "
      "AVG((SELECT COUNT(*) FROM attempts a WHERE a.session_id = s.id)) AS q "
      "FROM sessions s WHERE kind = 'alarm' AND outcome = 'dismissed'",
    )).first;
    final dismissed = (wake['n'] as int?) ?? 0;

    return ReportSummary(
      answered: (totals['n'] as int?) ?? 0,
      correct: (totals['c'] as int?) ?? 0,
      alarmsDismissed: dismissed,
      avgWakeTime: dismissed == 0
          ? null
          : Duration(milliseconds: (wake['ms'] as num).round()),
      avgWakeQuestions: dismissed == 0 ? null : (wake['q'] as num).toDouble(),
      days: [
        for (var i = 0; i < days; i++)
          DayStat(
            DateTime(firstDay.year, firstDay.month, firstDay.day + i),
            answered[i],
            correct[i],
          ),
      ],
      topics: topics,
    );
  }
}
