import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_alarm/data/app_database.dart';
import 'package:quiz_alarm/data/question_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  setUp(() => resetApp());

  test(
    'pickNext still works when every question was shown and answered right',
    () async {
      // This used to crash (and the alarm said "the question bank is empty")
      // on long streaks over a small topic.
      const topic = 'pharm-cns';
      final all = await QuestionRepository.getQuestions(topic);
      for (final q in all) {
        await QuestionRepository.recordAttempt(
          q.id,
          correct: true,
          mode: 'alarm',
        );
      }
      final q = await QuestionRepository.pickNext([
        topic,
      ], exclude: all.map((q) => q.id).toSet());
      expect(q, isNotNull);
    },
  );

  test('sessions keep the answers, timings and outcome', () async {
    final qs = await QuestionRepository.getQuestions('pharm-cns');
    final id = await QuestionRepository.startSession(
      'alarm',
      'Morning',
      alarmId: 7,
      requiredStreak: 3,
    );
    await QuestionRepository.recordAttempt(
      qs[0].id,
      correct: false,
      mode: 'alarm',
      sessionId: id,
      userAnswer: ' Diazepam ',
      timeTaken: const Duration(seconds: 12),
    );
    await QuestionRepository.recordAttempt(
      qs[1].id,
      correct: true,
      mode: 'alarm',
      sessionId: id,
      userAnswer: qs[1].correctAnswer,
      timeTaken: const Duration(seconds: 4),
    );
    await QuestionRepository.endSession(id, 'dismissed');

    final s = (await QuestionRepository.getSessions(kind: 'alarm')).single;
    expect(s.title, 'Morning');
    expect(s.outcome, 'dismissed');
    expect(s.requiredStreak, 3);
    expect(s.questions, 2);
    expect(s.correct, 1);
    expect(s.duration, isNotNull);
    expect(await QuestionRepository.getSessions(kind: 'revision'), isEmpty);

    final attempts = await QuestionRepository.getSessionAttempts(id!);
    expect(attempts.map((a) => a.question.id), [qs[0].id, qs[1].id]);
    expect(attempts[0].userAnswer, 'Diazepam');
    expect(attempts[0].correct, isFalse);
    expect(attempts[0].timeTaken, const Duration(seconds: 12));
    expect(attempts[0].question.explanation, isNotEmpty);
    expect(attempts[1].correct, isTrue);
  });

  test('a practice session with no answers leaves nothing behind', () async {
    final id = await QuestionRepository.startSession('bank', 'Empty');
    await QuestionRepository.endSession(id, 'finished');
    expect(await QuestionRepository.getSessions(), isEmpty);
  });

  test('report totals, days, topics and alarm averages', () async {
    final empty = await QuestionRepository.getReport();
    expect(empty.answered, 0);
    expect(empty.avgWakeTime, isNull);
    expect(empty.days.length, 14);

    final cns = await QuestionRepository.getQuestions('pharm-cns');
    final abx = await QuestionRepository.getQuestions('pharm-antimicrobials');
    final id = await QuestionRepository.startSession('alarm', 'A');
    for (var i = 0; i < 3; i++) {
      await QuestionRepository.recordAttempt(
        cns[i].id,
        correct: i > 0,
        mode: 'alarm',
        sessionId: id,
      );
    }
    await QuestionRepository.endSession(id, 'dismissed');
    await QuestionRepository.recordAttempt(
      abx[0].id,
      correct: false,
      mode: 'bank',
    );

    final r = await QuestionRepository.getReport();
    expect(r.answered, 4);
    expect(r.correct, 2);
    expect(r.alarmsDismissed, 1);
    expect(r.avgWakeQuestions, 3);
    expect(r.avgWakeTime, isNotNull);
    expect(r.days.last.answered, 4); // today is the last bar
    expect(r.days.last.correct, 2);
    // Weakest topic first.
    expect(r.topics.first.topic, 'Antimicrobials');
    expect(r.topics.first.accuracy, 0);
    expect(r.topics.last.answered, 3);
  });

  test('a database from the previous app version is upgraded, not wiped', () async {
    final dir = await Directory.systemTemp.createTemp('brainwake_test');
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE units(id TEXT PRIMARY KEY, name TEXT NOT NULL, '
            "description TEXT NOT NULL DEFAULT '', "
            'sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE topics(id TEXT PRIMARY KEY, unit_id TEXT NOT NULL, '
            'name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, '
            'is_custom INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE questions(id TEXT PRIMARY KEY, topic_id TEXT NOT NULL, '
            'type TEXT NOT NULL, text TEXT NOT NULL, text_key TEXT NOT NULL, '
            "options TEXT NOT NULL DEFAULT '[]', answer TEXT NOT NULL, "
            "alt_answers TEXT NOT NULL DEFAULT '[]', "
            "explanation TEXT NOT NULL DEFAULT '', "
            "source TEXT NOT NULL DEFAULT 'seed', created_at INTEGER NOT NULL)",
          );
          await db.execute(
            'CREATE UNIQUE INDEX idx_questions_unique '
            'ON questions(topic_id, text_key)',
          );
          await db.execute(
            'CREATE TABLE attempts(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'question_id TEXT NOT NULL REFERENCES questions(id) '
            'ON DELETE CASCADE, mode TEXT NOT NULL, correct INTEGER NOT NULL, '
            'answered_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('units', {
            'id': 'pharmacology',
            'name': 'Pharmacology',
          });
          await db.insert('topics', {
            'id': 'pharm-cns',
            'unit_id': 'pharmacology',
            'name': 'CNS',
          });
          await db.insert('questions', {
            'id': 'pharm-cns-002',
            'topic_id': 'pharm-cns',
            'type': 'saq',
            'text': 'Old text',
            'text_key': 'old text',
            'answer': 'Flumazenil',
            'created_at': 1,
          });
          await db.insert('questions', {
            'id': 'ai_1',
            'topic_id': 'pharm-cns',
            'type': 'saq',
            'text': 'My AI question?',
            'text_key': 'my ai question?',
            'answer': 'Yes',
            'source': 'ai',
            'created_at': 2,
          });
          await db.insert('attempts', {
            'question_id': 'pharm-cns-002',
            'mode': 'bank',
            'correct': 1,
            'answered_at': DateTime.now().millisecondsSinceEpoch,
          });
          await db.insert('meta', {'key': 'seed:pharmacology', 'value': '1'});
        },
      ),
    );
    await old.close();

    await AppDatabase.close();
    AppDatabase.pathOverride = path;
    QuestionRepository.resetForTest();

    // Old progress and the user's AI question survive; the new bank and
    // the new session features work.
    final stats = await QuestionRepository.getStats();
    expect(stats['pharm-cns']!.mastered, 1);
    final cns = await QuestionRepository.getQuestions('pharm-cns');
    expect(cns.map((q) => q.id), contains('ai_1'));
    expect(cns.length, 11);
    expect((await QuestionRepository.getReport()).answered, 1);
    final id = await QuestionRepository.startSession('bank', 'After upgrade');
    await QuestionRepository.recordAttempt(
      'ai_1',
      correct: true,
      mode: 'bank',
      sessionId: id,
      userAnswer: 'Yes',
    );
    await QuestionRepository.endSession(id, 'finished');
    expect((await QuestionRepository.getSessions()).single.questions, 1);

    await AppDatabase.close();
    await dir.delete(recursive: true);
  });
}
