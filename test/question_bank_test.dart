import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quiz_alarm/data/question_repository.dart';
import 'package:quiz_alarm/models/models.dart';
import 'package:quiz_alarm/services/question_service.dart';

import 'helpers.dart';

Map<String, dynamic> unitFile({int version = 1, String q1 = 'What is A?'}) => {
  'version': version,
  'unit': {'id': 'u', 'name': 'Unit'},
  'topics': [
    {
      'id': 't1',
      'name': 'One',
      'questions': [
        {
          'id': 'q1',
          'type': 'saq',
          'text': q1,
          'answer': 'A',
          'explanation': 'E1',
        },
        {'id': 'q2', 'type': 'saq', 'text': 'What is B?', 'answer': 'B'},
      ],
    },
    {'id': 't2', 'name': 'Two', 'questions': []},
  ],
};

void main() {
  setUp(() => resetApp());

  group('bundled pharmacology bank', () {
    test('is imported with topics, questions and explanations', () async {
      final units = await QuestionRepository.getUnits();
      expect(units.map((u) => u.id), contains('pharmacology'));
      final topics = await QuestionRepository.getTopics();
      expect(topics.length, greaterThanOrEqualTo(6));

      var total = 0;
      for (final t in topics) {
        final qs = await QuestionRepository.getQuestions(t.id);
        expect(qs, isNotEmpty, reason: t.name);
        for (final q in qs) {
          total++;
          expect(q.explanation, isNotEmpty, reason: q.id);
          expect(q.topic, t.name);
          if (q.type == QuestionType.mcq) {
            expect(q.options.length, 5, reason: q.id);
            expect(q.options, contains(q.correctAnswer), reason: q.id);
          }
        }
      }
      expect(total, greaterThanOrEqualTo(60));
    });

    test('old alarm topic names still resolve', () async {
      final all = await QuestionRepository.getTopics();
      expect(
        (await QuestionRepository.resolveTopicIds(['Pharmacology'])).length,
        all.length,
      );
      expect(await QuestionRepository.resolveTopicIds(['antimicrobials']), [
        'pharm-antimicrobials',
      ]);
      // Unknown or empty selections fall back to everything.
      expect(
        (await QuestionRepository.resolveTopicIds(['Nonsense'])).length,
        all.length,
      );
      expect(await QuestionRepository.describeSelection([]), 'All topics');
      expect(
        await QuestionRepository.describeSelection(['pharm-cns']),
        'Central nervous system drugs',
      );
    });
  });

  group('importUnit', () {
    test(
      're-importing a new version updates text and keeps progress',
      () async {
        await QuestionRepository.ensureReady();
        await QuestionRepository.importUnit(unitFile());
        await QuestionRepository.recordAttempt(
          'q1',
          correct: true,
          mode: 'bank',
        );

        // Same version: nothing changes.
        await QuestionRepository.importUnit(unitFile(q1: 'Ignored?'));
        expect(
          (await QuestionRepository.getQuestions('t1')).first.questionText,
          'What is A?',
        );

        final v2 = unitFile(version: 2, q1: 'What is A really?');
        (v2['topics'] as List).first['questions'].removeLast(); // drop q2
        await QuestionRepository.importUnit(v2);

        final qs = await QuestionRepository.getQuestions('t1');
        expect(qs.map((q) => q.id), ['q1']);
        expect(qs.first.questionText, 'What is A really?');
        final stats = await QuestionRepository.getStats();
        expect(stats['t1']!.seen, 1);
        expect(stats['t1']!.mastered, 1);
      },
    );

    test('generated questions survive a re-import', () async {
      await QuestionRepository.ensureReady();
      await QuestionRepository.importUnit(unitFile());
      await QuestionRepository.addQuestion(
        const Question(
          id: 'ai_1',
          topicId: 't1',
          topic: 'One',
          type: QuestionType.saq,
          questionText: 'AI question?',
          correctAnswer: 'Yes',
          source: 'ai',
        ),
      );
      await QuestionRepository.importUnit(unitFile(version: 2));
      expect(
        (await QuestionRepository.getQuestions('t1')).map((q) => q.id),
        containsAll(['q1', 'q2', 'ai_1']),
      );
    });
  });

  group('questions', () {
    const topic = 'pharm-cns';

    test('does not store a duplicate question', () async {
      final existing = (await QuestionRepository.getQuestions(topic)).first;
      final added = await QuestionRepository.addQuestion(
        Question(
          id: 'dup',
          topicId: topic,
          topic: 'x',
          type: QuestionType.saq,
          questionText: '  ${existing.questionText.toUpperCase()} ',
          correctAnswer: 'x',
        ),
      );
      expect(added, isFalse);
    });

    test(
      'pickNext: unseen first, then wrong ones, never a repeat in a row',
      () async {
        final all = await QuestionRepository.getQuestions(topic);
        final seenIds = <String>{};
        // Every question is served once before any repeats.
        for (var i = 0; i < all.length; i++) {
          final q = (await QuestionRepository.pickNext([topic]))!;
          expect(seenIds.add(q.id), isTrue);
          await QuestionRepository.recordAttempt(
            q.id,
            correct: q.id != all.first.id,
            mode: 'bank',
          );
        }
        // Now everything is seen; the one answered wrong comes back first.
        expect((await QuestionRepository.pickNext([topic]))!.id, all.first.id);
        // ...unless it was just shown.
        final other = await QuestionRepository.pickNext(
          [topic],
          exclude: {all.first.id},
        );
        expect(other!.id, isNot(all.first.id));
      },
    );

    test('custom topics can be added, found and deleted', () async {
      final t = await QuestionRepository.addCustomTopic(' Antimalarials ');
      expect(t.isCustom, isTrue);
      expect(
        (await QuestionRepository.addCustomTopic('antimalarials')).id,
        t.id,
      );
      expect(await QuestionRepository.resolveTopicIds(['Antimalarials']), [
        t.id,
      ]);
      await QuestionRepository.deleteCustomTopic(t.id);
      expect(await QuestionRepository.findTopicByName('Antimalarials'), isNull);
      // Built-in topics cannot be deleted this way.
      await QuestionRepository.deleteCustomTopic(topic);
      expect(await QuestionRepository.getQuestions(topic), isNotEmpty);
    });
  });

  test('AI questions saved by the old app version are imported', () async {
    await resetApp(
      prefs: {
        'offline_question_bank': jsonEncode([
          {
            'id': 'pharm_1',
            'topic': 'Pharmacology',
            'type': 'saq',
            'questionText': 'Old demo',
            'correctAnswer': 'x',
          },
          {
            'id': 'ai_99',
            'topic': 'Anatomy',
            'type': 'saq',
            'questionText': 'Longest bone?',
            'correctAnswer': 'Femur',
          },
        ]),
      },
    );
    final anatomy = await QuestionRepository.getTopics().then(
      (ts) => ts.firstWhere((t) => t.name == 'Anatomy'),
    );
    final qs = await QuestionRepository.getQuestions(anatomy.id);
    expect(qs.single.correctAnswer, 'Femur');
    expect(qs.single.source, 'ai');
  });

  group('AI generation', () {
    const topic = Topic(
      id: 'pharm-antimicrobials',
      unitId: 'pharmacology',
      name: 'Antimicrobials',
    );
    final two = [
      {
        'type': 'mcq',
        'questionText': 'Which drug treats MRSA?',
        'options': [
          'Vancomycin',
          'Amoxicillin',
          'Cefalexin',
          'Flucloxacillin',
          'Penicillin V',
        ],
        'correctAnswer': 'Vancomycin',
        'explanation': 'Vancomycin is active against MRSA.',
      },
      {
        'type': 'saq',
        'questionText': 'Which drug class does azithromycin belong to?',
        'correctAnswer': 'Macrolides',
        'acceptedAnswers': ['Macrolide'],
        'explanation': 'Azithromycin is a macrolide.',
      },
    ];

    test('stores new questions with explanations', () async {
      await resetApp(apiKey: 'k');
      final prompts = fakeGemini((_) => ok({'questions': two}));
      final r = await QuestionService.generateForTopic(topic);
      expect(r.error, isNull);
      expect(r.added, 2);
      final ai = (await QuestionRepository.getQuestions(topic.id))
          .where((q) => q.source == 'ai')
          .toList();
      expect(ai.length, 2);
      expect(ai.every((q) => q.explanation.isNotEmpty), isTrue);
      // The prompt names the unit and lists existing questions to avoid.
      expect(prompts.single, contains('Pharmacology - Antimicrobials'));
      expect(prompts.single, contains('How do penicillins kill bacteria?'));
    });

    test('accepts a bare list inside code fences', () async {
      await resetApp(apiKey: 'k');
      fakeGemini((_) => ok('```json\n${jsonEncode(two)}\n```'));
      expect((await QuestionService.generateForTopic(topic)).added, 2);
    });

    test('reports the reason when the API refuses', () async {
      await resetApp(apiKey: 'k');
      fakeGemini(
        (_) => http.Response('{"error":{"message":"Quota exceeded"}}', 429),
      );
      final r = await QuestionService.generateForTopic(topic);
      expect(r.added, 0);
      expect(r.error, contains('429'));
      expect(r.error, contains('Quota exceeded'));
    });

    test('retries without the schema if the model rejects it', () async {
      await resetApp(apiKey: 'k');
      var calls = 0;
      fakeGemini((body) {
        calls++;
        final hasSchema = (body['generationConfig'] as Map).containsKey(
          'responseSchema',
        );
        return hasSchema
            ? http.Response('{"error":{"message":"schema unsupported"}}', 400)
            : ok({'questions': two});
      });
      expect((await QuestionService.generateForTopic(topic)).added, 2);
      expect(calls, 2);
    });

    test('says so when nothing usable came back', () async {
      await resetApp(apiKey: 'k');
      fakeGemini(
        (_) => ok({
          'questions': [
            {'questionText': ''},
          ],
        }),
      );
      final r = await QuestionService.generateForTopic(topic);
      expect(r.added, 0);
      expect(r.error, contains('none were usable'));
    });

    test(
      'topUp does nothing without a key and fills low topics with one',
      () async {
        fakeGemini((_) => ok({'questions': two}));
        expect((await QuestionService.topUp(const [])).added, 0);

        await resetApp(apiKey: 'k');
        var n = 0;
        fakeGemini(
          (_) => ok({
            'questions': [
              {...two[1], 'questionText': 'Generated question ${n++}?'},
            ],
          }),
        );
        // Every seed topic has 10 unseen questions: nothing to do at target 5.
        expect((await QuestionService.topUp(const [])).added, 0);
        // With a higher target, at most two topics are filled per run.
        final r = await QuestionService.topUp(const [], targetUnseen: 11);
        expect(r.added, 2);
        expect(await QuestionService.lastStatus(), contains('Added 2'));
      },
    );
  });

  group('AI tutor', () {
    test(
      'explains, judges typed answers and saves a missing explanation',
      () async {
        await resetApp(apiKey: 'k');
        final t = await QuestionRepository.addCustomTopic('Anatomy');
        const q = Question(
          id: 'a1',
          topicId: '',
          topic: 'Anatomy',
          type: QuestionType.saq,
          questionText: 'Longest bone?',
          correctAnswer: 'Femur',
          source: 'ai',
        );
        await QuestionRepository.addQuestion(
          Question(
            id: q.id,
            topicId: t.id,
            topic: t.name,
            type: q.type,
            questionText: q.questionText,
            correctAnswer: q.correctAnswer,
            source: 'ai',
          ),
        );
        final prompts = fakeGemini(
          (_) => ok({
            'correct': true,
            'feedback': 'Yes, the thigh bone is the femur.',
            'explanation': 'The femur is the longest bone.',
          }),
        );
        final fb = await QuestionService.aiFeedback(q, 'thigh bone');
        expect(fb.correct, isTrue);
        expect(fb.feedback, contains('femur'));
        expect(prompts.single, contains('thigh bone'));
        expect(
          (await QuestionRepository.getQuestions(t.id)).single.explanation,
          'The femur is the longest bone.',
        );

        // "I don't know" is never marked correct, whatever the AI says.
        expect((await QuestionService.aiFeedback(q, '')).correct, isFalse);
        // A verdict the app already knows is not overridden.
        expect(
          (await QuestionService.aiFeedback(
            q,
            'tibia',
            knownVerdict: false,
          )).correct,
          isFalse,
        );
      },
    );
  });
}
