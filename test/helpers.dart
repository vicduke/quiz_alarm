/// Shared set-up for tests: an in-memory SQLite database, empty
/// preferences and a fake Gemini server.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quiz_alarm/data/app_database.dart';
import 'package:quiz_alarm/data/question_repository.dart';
import 'package:quiz_alarm/services/gemini_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Call from setUp(). Gives every test a fresh, empty world.
Future<void> resetApp({
  Map<String, Object> prefs = const {},
  String? apiKey,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  await AppDatabase.close();
  AppDatabase.factoryOverride = databaseFactoryFfiNoIsolate;
  AppDatabase.pathOverride = inMemoryDatabasePath;
  QuestionRepository.resetForTest();
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({'gemini_api_key': ?apiKey});
}

/// Wraps [text] the way the Gemini API returns model output.
String geminiBody(String text) => jsonEncode({
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': text},
        ],
      },
    },
  ],
});

/// Makes every Gemini call answer with [reply] (given the request body).
/// Returns the list that collects the prompts that were sent.
List<String> fakeGemini(
  http.Response Function(Map<String, dynamic> body) reply,
) {
  final prompts = <String>[];
  GeminiClient.httpClient = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    prompts.add(body['contents'][0]['parts'][0]['text'] as String);
    return reply(body);
  });
  return prompts;
}

http.Response ok(Object json) => http.Response.bytes(
  utf8.encode(geminiBody(json is String ? json : jsonEncode(json))),
  200,
);
