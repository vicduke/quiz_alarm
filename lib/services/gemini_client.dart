/// Talks to the Gemini REST API and stores the user's key and model name.
/// Everything AI-related goes through [GeminiClient.generateJson].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => message;
}

class GeminiClient {
  static const String _apiKeyPref = 'gemini_api_key';
  static const String _modelPref = 'gemini_model';
  static const String defaultModel = 'gemini-3.5-flash';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  /// Tests replace this with a fake.
  @visibleForTesting
  static http.Client httpClient = http.Client();

  // ------------------------------------------------------------------ keys

  /// The API key lives in secure storage. A key saved by an older version in
  /// plain SharedPreferences is moved over the first time it is read.
  static Future<String?> getApiKey() async {
    try {
      final stored = await _secure.read(key: _apiKeyPref);
      if (stored != null && stored.isNotEmpty) return stored;

      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_apiKeyPref);
      if (legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: _apiKeyPref, value: legacy);
        await prefs.remove(_apiKeyPref);
        return legacy;
      }
    } catch (e) {
      debugPrint('Reading API key failed: $e');
    }
    return null;
  }

  static Future<bool> hasApiKey() async =>
      ((await getApiKey()) ?? '').isNotEmpty;

  static Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _secure.delete(key: _apiKeyPref);
    } else {
      await _secure.write(key: _apiKeyPref, value: trimmed);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyPref);
  }

  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final m = prefs.getString(_modelPref)?.trim();
    return (m == null || m.isEmpty) ? defaultModel : m;
  }

  static Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    final m = model.trim();
    if (m.isEmpty) {
      await prefs.remove(_modelPref);
    } else {
      await prefs.setString(_modelPref, m);
    }
  }

  // ------------------------------------------------------------------ calls

  /// Sends [prompt] and returns the decoded JSON the model replied with.
  /// [schema] (Gemini `responseSchema`) pins the shape of the reply; if the
  /// chosen model rejects the schema the call is repeated without it.
  /// Throws [GeminiException] with a readable reason on any failure.
  static Future<dynamic> generateJson(
    String prompt, {
    required Duration timeout,
    Map<String, dynamic>? schema,
  }) async {
    try {
      return decodeJson(await _post(prompt, timeout: timeout, schema: schema));
    } on GeminiException catch (e) {
      if (schema == null || !e.message.startsWith('HTTP 400')) rethrow;
      debugPrint('Retrying without a response schema: $e');
      return decodeJson(await _post(prompt, timeout: timeout));
    } on FormatException {
      throw const GeminiException('The model replied with unreadable JSON.');
    }
  }

  static Future<String> _post(
    String prompt, {
    required Duration timeout,
    Map<String, dynamic>? schema,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiException('No API key saved.');
    }
    final model = await getModel();
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    );

    final http.Response res;
    try {
      res = await httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'responseSchema': ?schema,
              },
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw GeminiException(
        'The request timed out after ${timeout.inSeconds} s.',
      );
    } catch (e) {
      throw GeminiException('Network error: $e');
    }

    if (res.statusCode != 200) {
      var detail = res.body;
      try {
        detail = (jsonDecode(res.body)['error']['message'] ?? res.body)
            .toString();
      } catch (_) {}
      throw GeminiException('HTTP ${res.statusCode} (model "$model"): $detail');
    }

    final text = extractText(utf8.decode(res.bodyBytes));
    if (text.trim().isEmpty) {
      throw const GeminiException(
        'The model returned an empty or blocked reply.',
      );
    }
    return text;
  }

  /// Joins the text of every non-"thought" part of the first candidate.
  /// (Thinking models can put reasoning parts before the real answer.)
  @visibleForTesting
  static String extractText(String body) {
    try {
      final data = jsonDecode(body);
      final parts = data['candidates'][0]['content']['parts'] as List;
      return parts
          .where((p) => p is Map && p['thought'] != true && p['text'] is String)
          .map((p) => p['text'] as String)
          .join();
    } catch (_) {
      return '';
    }
  }

  /// Decodes model output that should be JSON, tolerating code fences and
  /// stray text before or after the JSON value.
  @visibleForTesting
  static dynamic decodeJson(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?'), '');
      t = t.replaceFirst(RegExp(r'```$'), '').trim();
    }
    try {
      return jsonDecode(t);
    } on FormatException {
      final start = t.indexOf(RegExp(r'[\[{]'));
      final end = t.lastIndexOf(RegExp(r'[\]}]'));
      if (start == -1 || end <= start) rethrow;
      return jsonDecode(t.substring(start, end + 1));
    }
  }

  /// Returns null if the key and model work, otherwise a readable error.
  static Future<String?> testConnection() async {
    try {
      final data = await generateJson(
        'Reply with exactly this JSON: {"ok": true}',
        timeout: const Duration(seconds: 15),
      );
      return (data is Map && data['ok'] == true)
          ? null
          : 'Unexpected reply: $data';
    } catch (e) {
      return e.toString();
    }
  }
}
