import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/models.dart';

class QuestionService {
  static const String _bankKey = 'offline_question_bank';
  static const String _apiKeyPref = 'gemini_api_key';

  static final List<Question> _demoQuestions = [
    // Pharmacology Demos
    Question(
      id: 'pharm_1',
      topic: 'Pharmacology',
      type: QuestionType.mcq,
      questionText: 'What is the primary mechanism of action of Aspirin?',
      options: [
        'COX inhibitor',
        'Beta blocker',
        'Calcium channel blocker',
        'ACE inhibitor',
      ],
      correctAnswer: 'COX inhibitor',
    ),
    Question(
      id: 'pharm_2',
      topic: 'Pharmacology',
      type: QuestionType.saq,
      questionText: 'What is the specific antidote for opioid overdose?',
      correctAnswer: 'Naloxone',
    ),
    Question(
      id: 'pharm_3',
      topic: 'Pharmacology',
      type: QuestionType.mcq,
      questionText: 'Which antibiotic class does Penicillin belong to?',
      options: [
        'Beta-lactams',
        'Macrolides',
        'Tetracyclines',
        'Aminoglycosides',
      ],
      correctAnswer: 'Beta-lactams',
    ),
    // General Demos
    Question(
      id: 'gen_1',
      topic: 'General Knowledge',
      type: QuestionType.mcq,
      questionText: 'What is the powerhouse of the cell?',
      options: ['Nucleus', 'Mitochondria', 'Ribosome', 'Golgi'],
      correctAnswer: 'Mitochondria',
    ),
  ];

  static Future<List<Question>> getOfflineBank() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_bankKey);
    if (raw == null) {
      await saveOfflineBank(_demoQuestions);
      return _demoQuestions;
    }
    final List decoded = jsonDecode(raw);
    return decoded.map((e) => Question.fromJson(e)).toList();
  }

  static Future<void> saveOfflineBank(List<Question> questions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _bankKey,
      jsonEncode(questions.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> addQuestionToBank(Question q) async {
    final bank = await getOfflineBank();
    bank.add(q);
    await saveOfflineBank(bank);
  }

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyPref);
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key.trim());
  }

  static Future<Question> getNextQuestion(List<String> topics) async {
    final rand = Random();
    final selectedTopic = topics.isNotEmpty
        ? topics[rand.nextInt(topics.length)]
        : 'General Knowledge';
    final isMcq = rand.nextBool();

    final apiKey = await getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
          ),
        );
        final prompt =
            '''
Generate a ${isMcq ? 'Multiple Choice Question (mcq) with 4 options' : 'Short Answer Question (saq)'} about: "$selectedTopic". Return JSON: {"topic": "$selectedTopic", "type": "${isMcq ? 'mcq' : 'saq'}", "questionText": "...", "options": ${isMcq ? '["A", "B", "C", "D"]' : '[]'}, "correctAnswer": "..."}
''';
        final response = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 7));
        if (response.text != null) {
          final data = jsonDecode(response.text!);
          final generated = Question.fromJson(data);
          await addQuestionToBank(generated);
          return generated;
        }
      } catch (e) {
        debugPrint('AI failed: $e');
      }
    }
    // Offline Fallback
    final bank = await getOfflineBank();
    final matches = bank
        .where(
          (q) => topics.any(
            (t) => q.topic.toLowerCase().contains(t.toLowerCase()),
          ),
        )
        .toList();
    final pool = matches.isNotEmpty ? matches : bank;
    return pool[rand.nextInt(pool.length)];
  }

  static Future<bool> gradeAnswer(Question q, String userAnswer) async {
    final cleanUser = userAnswer.trim().toLowerCase();
    final cleanCorrect = q.correctAnswer.trim().toLowerCase();
    if (cleanUser.isEmpty) return false;
    if (cleanUser == cleanCorrect) return true;
    if (q.type == QuestionType.mcq) return false;

    final apiKey = await getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
          ),
        );
        final prompt =
            'Question: "${q.questionText}"\nExpected: "${q.correctAnswer}"\nUser: "$userAnswer"\nIs this conceptually correct? Return JSON: {"correct": true/false}';
        final response = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 6));
        if (response.text != null) {
          return jsonDecode(response.text!)['correct'] == true;
        }
      } catch (e) {
        debugPrint('AI Grading failed: $e');
      }
    }
    return cleanUser.contains(cleanCorrect) || cleanCorrect.contains(cleanUser);
  }
}
