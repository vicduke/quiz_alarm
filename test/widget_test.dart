import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quiz_alarm/models/models.dart';
import 'package:quiz_alarm/services/alarm_provider.dart';
import 'package:quiz_alarm/services/question_service.dart';

void main() {
  group('calculateNextTrigger', () {
    // Friday 13 Nov 2026, 10:00
    final now = DateTime(2026, 11, 13, 10, 0);

    test('ring-once, time already passed today -> tomorrow', () {
      final next = calculateNextTrigger(
        const TimeOfDay(hour: 9, minute: 0),
        const [],
        now,
      );
      expect(next, DateTime(2026, 11, 14, 9, 0));
    });

    test('ring-once, time later today -> today', () {
      final next = calculateNextTrigger(
        const TimeOfDay(hour: 11, minute: 0),
        const [],
        now,
      );
      expect(next, DateTime(2026, 11, 13, 11, 0));
    });

    test('repeating on Mondays -> next Monday', () {
      final next = calculateNextTrigger(
        const TimeOfDay(hour: 11, minute: 0),
        const [1],
        now,
      );
      expect(next, DateTime(2026, 11, 16, 11, 0));
    });

    test('exactly now counts as passed -> next matching day', () {
      final next = calculateNextTrigger(
        const TimeOfDay(hour: 10, minute: 0),
        const [5], // Friday
        now,
      );
      expect(next, DateTime(2026, 11, 20, 10, 0));
    });
  });

  group('QuestionService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('does not store a duplicate question', () async {
      final bank = await QuestionService.getOfflineBank();
      final dup = Question(
        id: 'dup',
        topic: 'Pharmacology',
        type: QuestionType.saq,
        questionText: '  ${bank.first.questionText.toUpperCase()}  ',
        correctAnswer: 'x',
      );
      expect(await QuestionService.addQuestionToBank(dup), isFalse);
      expect((await QuestionService.getOfflineBank()).length, bank.length);
    });

    test('never serves the same question twice in a row', () async {
      String? last;
      for (var i = 0; i < 30; i++) {
        final q = await QuestionService.getNextQuestion(['Pharmacology']);
        expect(q.id, isNot(last));
        last = q.id;
      }
    });

    test('recovers from a corrupted saved bank', () async {
      SharedPreferences.setMockInitialValues({
        'offline_question_bank': 'not json',
      });
      expect((await QuestionService.getOfflineBank()), isNotEmpty);
    });

    test('exact MCQ answer is graded correct, wrong one is not', () async {
      final q = Question(
        id: 'q',
        topic: 'T',
        type: QuestionType.mcq,
        questionText: 'Q?',
        options: const ['A', 'B'],
        correctAnswer: 'A',
      );
      expect(await QuestionService.gradeAnswer(q, 'a'), isTrue);
      expect(await QuestionService.gradeAnswer(q, 'B'), isFalse);
    });
  });

  group('answersMatch (offline SAQ grading)', () {
    test('a single letter never passes', () {
      expect(answersMatch('n', 'Naloxone'), isFalse);
      expect(answersMatch('a', 'Naloxone'), isFalse);
      expect(answersMatch('na', 'Naloxone'), isFalse);
    });

    test('a fragment of the answer does not pass', () {
      expect(answersMatch('nal', 'Naloxone'), isFalse);
      expect(answersMatch('cox', 'COX inhibitor'), isFalse);
    });

    test('exact, case and punctuation differences pass', () {
      expect(answersMatch('naloxone', 'Naloxone'), isTrue);
      expect(answersMatch('  NALOXONE. ', 'Naloxone'), isTrue);
      expect(answersMatch('beta lactams', 'Beta-lactams'), isTrue);
    });

    test('extra words around the answer pass', () {
      expect(answersMatch('I think it is naloxone (narcan)', 'Naloxone'), isTrue);
    });

    test('small typos on longer words pass', () {
      expect(answersMatch('naloxon', 'Naloxone'), isTrue);
      expect(answersMatch('beta lactam', 'Beta-lactams'), isTrue);
    });

    test('wrong answers fail', () {
      expect(answersMatch('morphine', 'Naloxone'), isFalse);
    });
  });

  group('validateGenerated (AI question checks)', () {
    Map<String, dynamic> mcq({List? options, String answer = 'B'}) => {
      'questionText': 'Which letter?',
      'options': options ?? ['A', 'B', 'C', 'D'],
      'correctAnswer': answer,
    };

    test('accepts a valid MCQ and keeps the right answer after shuffling', () {
      final q = QuestionService.validateGenerated(
        mcq(),
        'Pharmacology',
        true,
        rng: Random(1),
      );
      expect(q, isNotNull);
      expect(q!.options.length, 4);
      expect(q.options, contains(q.correctAnswer));
      expect(q.correctAnswer, 'B');
      expect(q.topic, 'Pharmacology');
    });

    test('rejects an answer that is not among the options', () {
      expect(QuestionService.validateGenerated(mcq(answer: 'Z'), 'T', true), isNull);
    });

    test('rejects the wrong number of options or duplicates', () {
      expect(
        QuestionService.validateGenerated(mcq(options: ['A', 'B', 'C']), 'T', true),
        isNull,
      );
      expect(
        QuestionService.validateGenerated(
          mcq(options: ['A', 'a', 'C', 'D'], answer: 'A'),
          'T',
          true,
        ),
        isNull,
      );
    });

    test('rejects empty text or non-map data', () {
      expect(QuestionService.validateGenerated('nope', 'T', true), isNull);
      expect(
        QuestionService.validateGenerated(
          {'questionText': ' ', 'correctAnswer': 'x'},
          'T',
          false,
        ),
        isNull,
      );
    });

    test('accepts a valid SAQ', () {
      final q = QuestionService.validateGenerated(
        {'questionText': 'Antidote for opioids?', 'correctAnswer': 'Naloxone'},
        'Pharmacology',
        false,
      );
      expect(q?.type, QuestionType.saq);
    });
  });
}
