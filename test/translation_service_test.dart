import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/translation_service.dart';

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
