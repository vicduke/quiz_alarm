import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quiz_alarm/models/models.dart';
import 'package:quiz_alarm/services/alarm_provider.dart';
import 'package:quiz_alarm/services/gemini_client.dart';
import 'package:quiz_alarm/services/question_service.dart';

void main() {
  group('calculateNextTrigger', () {
    // Friday 13 Nov 2026, 10:00
    final now = DateTime(2026, 11, 13, 10, 0);

    test('ring-once, time already passed today -> tomorrow', () {
      expect(
        calculateNextTrigger(
          const TimeOfDay(hour: 9, minute: 0),
          const [],
          now,
        ),
        DateTime(2026, 11, 14, 9, 0),
      );
    });

    test('ring-once, time later today -> today', () {
      expect(
        calculateNextTrigger(
          const TimeOfDay(hour: 11, minute: 0),
          const [],
          now,
        ),
        DateTime(2026, 11, 13, 11, 0),
      );
    });

    test('repeating on Mondays -> next Monday', () {
      expect(
        calculateNextTrigger(const TimeOfDay(hour: 11, minute: 0), const [
          1,
        ], now),
        DateTime(2026, 11, 16, 11, 0),
      );
    });

    test('exactly now counts as passed -> next matching day', () {
      expect(
        calculateNextTrigger(const TimeOfDay(hour: 10, minute: 0), const [
          5,
        ], now),
        DateTime(2026, 11, 20, 10, 0),
      );
    });
  });

  group('describeTimeUntil', () {
    final now = DateTime(2026, 11, 13, 10, 0);
    test('minutes, hours and days', () {
      expect(
        describeTimeUntil(now.add(const Duration(seconds: 20)), now),
        'in less than a minute',
      );
      expect(
        describeTimeUntil(now.add(const Duration(minutes: 5)), now),
        'in 5 minutes',
      );
      expect(
        describeTimeUntil(now.add(const Duration(hours: 1, minutes: 1)), now),
        'in 1 hour 1 minute',
      );
      expect(
        describeTimeUntil(now.add(const Duration(days: 3, hours: 1)), now),
        'in 3 days 1 hour',
      );
    });
  });

  group('answersMatch (local marking)', () {
    test('a single letter never passes', () {
      expect(answersMatch('n', 'Naloxone'), isFalse);
      expect(answersMatch('a', 'Aspirin'), isFalse);
      expect(answersMatch('', 'Naloxone'), isFalse);
    });

    test('a fragment of the answer does not pass', () {
      expect(answersMatch('nal', 'Naloxone'), isFalse);
      expect(answersMatch('beta', 'Beta blocker'), isFalse);
    });

    test('exact, case and punctuation differences pass', () {
      expect(answersMatch('naloxone', 'Naloxone'), isTrue);
      expect(answersMatch('  NALOXONE. ', 'Naloxone'), isTrue);
      expect(answersMatch('beta lactams', 'Beta-lactams'), isTrue);
    });

    test('extra words around the answer pass', () {
      expect(answersMatch('it is naloxone', 'Naloxone'), isTrue);
    });

    test('small typos on longer words pass', () {
      expect(answersMatch('naloxon', 'Naloxone'), isTrue);
      expect(answersMatch('mitocondria', 'Mitochondria'), isTrue);
    });

    test('wrong answers fail', () {
      expect(answersMatch('naltrexone', 'Naloxone'), isFalse);
      expect(answersMatch('flumazenil', 'Naloxone'), isFalse);
    });
  });

  group('isLocallyCorrect', () {
    const saq = Question(
      id: 'q',
      topic: 'ANS',
      type: QuestionType.saq,
      questionText: 'First-line drug for anaphylaxis?',
      correctAnswer: 'Adrenaline',
      altAnswers: ['Epinephrine', 'B6'],
    );
    const mcq = Question(
      id: 'm',
      topic: 'ANS',
      type: QuestionType.mcq,
      questionText: 'Pick',
      options: ['Liver', 'Kidney', 'Lungs', 'Spleen'],
      correctAnswer: 'Liver',
    );

    test('accepted alternatives count for typed answers', () {
      expect(isLocallyCorrect(saq, 'epinephrine'), isTrue);
      expect(isLocallyCorrect(saq, 'IM adrenaline'), isTrue);
      expect(isLocallyCorrect(saq, 'b6'), isTrue); // short but exact
      expect(isLocallyCorrect(saq, 'atropine'), isFalse);
      expect(isLocallyCorrect(saq, ''), isFalse);
    });

    test('MCQ needs the exact option', () {
      expect(isLocallyCorrect(mcq, 'liver'), isTrue);
      expect(isLocallyCorrect(mcq, 'Kidney'), isFalse);
    });

    test('certainVerdict leaves inexact typed answers to the AI', () {
      expect(QuestionService.certainVerdict(mcq, 'Kidney'), isFalse);
      expect(QuestionService.certainVerdict(saq, 'Adrenaline'), isTrue);
      expect(
        QuestionService.certainVerdict(saq, 'adrenalin injection'),
        isNull,
      );
      expect(QuestionService.certainVerdict(saq, ''), isFalse);
    });
  });

  group('validateGenerated (AI question checks)', () {
    const topic = Topic(id: 't1', unitId: 'u1', name: 'Antimicrobials');
    Map<String, dynamic> mcq(List<String> options, String answer) => {
      'type': 'mcq',
      'questionText': 'Pick one',
      'options': options,
      'correctAnswer': answer,
      'explanation': 'Because.',
    };

    test('accepts a valid MCQ and keeps the right answer after shuffling', () {
      final q = QuestionService.validateGenerated(
        mcq(['A1', 'B2', 'C3', 'D4'], 'c3'),
        topic,
        rng: Random(1),
      );
      expect(q, isNotNull);
      expect(q!.options.toSet(), {'A1', 'B2', 'C3', 'D4'});
      expect(q.correctAnswer, 'C3');
      expect(q.topicId, 't1');
      expect(q.explanation, 'Because.');
      expect(q.source, 'ai');
    });

    test('rejects an answer that is not among the options', () {
      expect(
        QuestionService.validateGenerated(
          mcq(['A', 'B', 'C', 'D'], 'E'),
          topic,
        ),
        isNull,
      );
    });

    test('rejects the wrong number of options or duplicates', () {
      expect(
        QuestionService.validateGenerated(mcq(['A', 'B', 'C'], 'A'), topic),
        isNull,
      );
      expect(
        QuestionService.validateGenerated(
          mcq(['A', 'a', 'C', 'D'], 'A'),
          topic,
        ),
        isNull,
      );
    });

    test('rejects empty text or non-map data', () {
      expect(QuestionService.validateGenerated('nope', topic), isNull);
      expect(
        QuestionService.validateGenerated({
          'questionText': ' ',
          'correctAnswer': 'x',
        }, topic),
        isNull,
      );
    });

    test('accepts a valid SAQ with accepted answers', () {
      final q = QuestionService.validateGenerated({
        'type': 'saq',
        'questionText': 'Antidote for opioids?',
        'options': [],
        'correctAnswer': 'Naloxone',
        'acceptedAnswers': ['Narcan', 'Naloxone'],
      }, topic);
      expect(q!.type, QuestionType.saq);
      expect(q.altAnswers, ['Narcan']);
    });

    test('questionItems copes with every reply shape', () {
      expect(QuestionService.questionItems([1, 2]), [1, 2]);
      expect(
        QuestionService.questionItems({
          'questions': [1],
        }),
        [1],
      );
      expect(QuestionService.questionItems({'questionText': 'x'}).length, 1);
      expect(QuestionService.questionItems('text'), isEmpty);
    });
  });

  group('GeminiClient parsing', () {
    test('decodeJson strips fences and surrounding text', () {
      expect(GeminiClient.decodeJson('```json\n{"ok": true}\n```'), {
        'ok': true,
      });
      expect(GeminiClient.decodeJson('Here you go: [1, 2] Enjoy'), [1, 2]);
    });

    test('extractText joins parts and skips thoughts', () {
      const body =
          '{"candidates":[{"content":{"parts":['
          '{"text":"thinking...","thought":true},'
          '{"text":"{\\"a\\":"},{"text":"1}"}]}}]}';
      expect(GeminiClient.extractText(body), '{"a":1}');
      expect(GeminiClient.extractText('{"candidates":[]}'), '');
    });
  });
}
