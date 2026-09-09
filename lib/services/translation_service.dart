import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationResult {
  const TranslationResult({
    required this.text,
    required this.sourceLanguage,
    this.isOfflinePreview = false,
  });

  final String text;
  final String sourceLanguage;
  final bool isOfflinePreview;
}

class TranslationService extends ChangeNotifier {
  static const _endpoint = String.fromEnvironment('TRANSLATION_API_URL');
  static const _apiKey = String.fromEnvironment('TRANSLATION_API_KEY');

  final http.Client _client = http.Client();
  bool _isReady = false;
  bool _isTranslating = false;
  String? _error;

  bool get isReady => _isReady;
  bool get isTranslating => _isTranslating;
  bool get hasRemoteProvider => _endpoint.isNotEmpty;
  String? get error => _error;

  Future<void> init() async {
    _isReady = true;
    notifyListeners();
  }

  TranslationResult? translateOffline({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return null;
    if (sourceLanguage == targetLanguage) {
      return TranslationResult(
        text: cleanText,
        sourceLanguage: sourceLanguage,
        isOfflinePreview: true,
      );
    }
    return TranslationResult(
      text: _offlineTranslation(
        cleanText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
      sourceLanguage: sourceLanguage == 'auto' ? 'en' : sourceLanguage,
      isOfflinePreview: true,
    );
  }

  Future<TranslationResult?> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || _isTranslating) return null;

    _isTranslating = true;
    _error = null;
    notifyListeners();

    try {
      if (sourceLanguage == targetLanguage) {
        return TranslationResult(
          text: cleanText,
          sourceLanguage: sourceLanguage,
        );
      }

      if (_endpoint.isNotEmpty) {
        return await _remoteTranslation(
          text: cleanText,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );
      }

      return translateOffline(
        text: cleanText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
    } catch (_) {
      _error = 'Translation request failed.';
      return null;
    } finally {
      _isTranslating = false;
      notifyListeners();
    }
  }

  Future<TranslationResult> _remoteTranslation({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
          },
          body: jsonEncode({
            'q': text,
            'source': sourceLanguage,
            'target': targetLanguage,
            'format': 'text',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Translation provider returned ${response.statusCode}.',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid translation response.');
    }

    final translated =
        payload['translatedText'] ??
        (payload['data'] is Map ? payload['data']['translatedText'] : null);
    if (translated is! String || translated.trim().isEmpty) {
      throw const FormatException('Translation text is missing.');
    }

    return TranslationResult(
      text: translated.trim(),
      sourceLanguage:
          (payload['detectedLanguage'] as String?) ?? sourceLanguage,
    );
  }

  String _offlineTranslation(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final normalized = _normalizePhrase(text);
    final normalizedSource = sourceLanguage
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first;
    final normalizedTarget = targetLanguage
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first;

    if (normalizedSource == 'auto' || normalizedSource == 'en') {
      final exact = _offlinePhrases[normalized]?[normalizedTarget];
      if (exact != null) return exact;
    } else {
      for (final phrase in _offlinePhrases.entries) {
        final sourceText = phrase.value[normalizedSource];
        if (sourceText == null || _normalizePhrase(sourceText) != normalized) {
          continue;
        }
        if (normalizedTarget == 'en') {
          return _offlineEnglishDisplay[phrase.key] ?? phrase.key;
        }
        return phrase.value[normalizedTarget] ?? text;
      }
    }

    // Never pretend arbitrary text was translated. In unconfigured builds the
    // original stays visible and is explicitly marked as an offline preview.
    return text;
  }

  String _normalizePhrase(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?؟？。！]+$'), '')
        .trim();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

const _offlineEnglishDisplay = <String, String>{
  'hello': 'Hello',
  'how are you': 'How are you?',
  'thank you': 'Thank you',
  'nice to meet you': 'Nice to meet you',
  'have a nice day': 'Have a nice day',
  'i am from globoverse': 'I am from GloboVerse',
};

const _offlinePhrases = <String, Map<String, String>>{
  'hello': {
    'tg': 'Салом',
    'ru': 'Привет',
    'uz': 'Salom',
    'es': 'Hola',
    'fr': 'Bonjour',
    'de': 'Hallo',
    'ar': 'مرحباً',
    'fa': 'سلام',
    'ja': 'こんにちは',
    'zh': '你好',
  },
  'how are you': {
    'tg': 'Шумо чӣ хелед?',
    'ru': 'Как дела?',
    'uz': 'Qalaysiz?',
    'es': '¿Cómo estás?',
    'fr': 'Comment allez-vous ?',
    'de': 'Wie geht es dir?',
    'ar': 'كيف حالك؟',
    'fa': 'حال شما چطور است؟',
    'ja': 'お元気ですか？',
    'zh': '你好吗？',
  },
  'thank you': {
    'tg': 'Ташаккур',
    'ru': 'Спасибо',
    'uz': 'Rahmat',
    'es': 'Gracias',
    'fr': 'Merci',
    'de': 'Danke',
    'ar': 'شكراً',
    'fa': 'متشکرم',
    'ja': 'ありがとう',
    'zh': '谢谢',
  },
  'nice to meet you': {
    'tg': 'Аз шиносоӣ шодам',
    'ru': 'Приятно познакомиться',
    'uz': 'Tanishganimdan xursandman',
    'es': 'Mucho gusto',
    'fr': 'Enchanté',
    'de': 'Freut mich, dich kennenzulernen',
    'ar': 'سعيد بلقائك',
    'fa': 'از آشنایی با شما خوشحالم',
    'ja': 'はじめまして',
    'zh': '很高兴认识你',
  },
  'have a nice day': {
    'tg': 'Рӯзи хуб дошта бошед',
    'ru': 'Хорошего дня',
    'uz': 'Kuningiz xayrli o‘tsin',
    'es': 'Que tengas un buen día',
    'fr': 'Bonne journée',
    'de': 'Einen schönen Tag noch',
    'ar': 'أتمنى لك يوماً سعيداً',
    'fa': 'روز خوبی داشته باشید',
    'ja': '良い一日を',
    'zh': '祝你今天愉快',
  },
  'i am from globoverse': {
    'tg': 'Ман аз GloboVerse ҳастам',
    'ru': 'Я из GloboVerse',
    'uz': 'Men GloboVerse’danman',
    'es': 'Soy de GloboVerse',
    'fr': 'Je viens de GloboVerse',
    'de': 'Ich komme aus GloboVerse',
    'ar': 'أنا من GloboVerse',
    'fa': 'من از GloboVerse هستم',
    'ja': 'GloboVerseから来ました',
    'zh': '我来自GloboVerse',
  },
};
