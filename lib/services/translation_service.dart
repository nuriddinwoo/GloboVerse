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

      return TranslationResult(
        text: _offlineTranslation(cleanText, targetLanguage),
        sourceLanguage: sourceLanguage == 'auto' ? 'en' : sourceLanguage,
        isOfflinePreview: true,
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

  String _offlineTranslation(String text, String targetLanguage) {
    final normalized = text.toLowerCase().trim().replaceAll(
      RegExp(r'[.!?]+$'),
      '',
    );
    final exact = _offlinePhrases[normalized]?[targetLanguage];
    if (exact != null) return exact;

    // Never pretend arbitrary text was translated. In unconfigured builds the
    // original stays visible and is explicitly marked as an offline preview.
    return text;
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

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
};
