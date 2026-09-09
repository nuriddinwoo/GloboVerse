import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/translation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('bundled offline phrases translate without a remote endpoint', () async {
    final service = TranslationService();
    await service.init();

    final result = await service.translate(
      text: 'Hello!',
      sourceLanguage: 'en',
      targetLanguage: 'tg',
    );

    expect(result?.text, 'Салом');
    expect(result?.isOfflinePreview, isTrue);
    service.dispose();
  });

  test('offline phrases translate back to English', () async {
    final service = TranslationService();
    await service.init();

    final result = await service.translate(
      text: 'Шумо чӣ хелед?',
      sourceLanguage: 'tg',
      targetLanguage: 'en',
    );

    expect(result?.text, 'How are you?');
    expect(result?.isOfflinePreview, isTrue);
    service.dispose();
  });

  test('remote translations can run concurrently', () async {
    final responses = <Completer<http.Response>>[];
    final bothStarted = Completer<void>();
    final client = MockClient((_) async {
      final response = Completer<http.Response>();
      responses.add(response);
      if (responses.length == 2 && !bothStarted.isCompleted) {
        bothStarted.complete();
      }
      return response.future;
    });
    final service = TranslationService(
      client: client,
      endpoint: 'https://translate.example.com',
    );
    await service.init();

    final first = service.translate(
      text: 'Hello',
      sourceLanguage: 'en',
      targetLanguage: 'tg',
    );
    final second = service.translate(
      text: 'Thank you',
      sourceLanguage: 'en',
      targetLanguage: 'ru',
    );
    await bothStarted.future;
    expect(service.isTranslating, isTrue);

    responses.first.complete(http.Response('{"translatedText":"Салом"}', 200));
    expect((await first)?.text, 'Салом');
    expect(service.isTranslating, isTrue);

    responses.last.complete(http.Response('{"translatedText":"Спасибо"}', 200));
    expect((await second)?.text, 'Спасибо');
    expect(service.isTranslating, isFalse);
    service.dispose();
  });

  test(
    'unknown offline text stays visible instead of faking a translation',
    () async {
      final service = TranslationService();
      await service.init();

      final result = await service.translate(
        text: 'A sentence not in the phrasebook',
        sourceLanguage: 'en',
        targetLanguage: 'es',
      );

      expect(result?.text, 'A sentence not in the phrasebook');
      expect(result?.isOfflinePreview, isTrue);
      service.dispose();
    },
  );
}
