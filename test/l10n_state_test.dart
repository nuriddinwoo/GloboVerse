import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/l10n/l10n_state.dart';
import 'package:globoverse/l10n/languages.dart';

void main() {
  group('L10nState', () {
    test('normalizes invalid language codes to English', () {
      final state = L10nState('not-a-language');

      expect(state.code, 'en');
      expect(state.locale.languageCode, 'en');
    });

    test('interpolates values in Tajik translations', () {
      final state = L10nState('tg');

      expect(state.t('hello', {'name': 'Нуриддин'}), 'Салом, Нуриддин');
    });

    test('uses English UI copy when a catalog has no bundled copy', () {
      final state = L10nState('ab');

      expect(state.code, 'ab');
      expect(state.t('continue'), 'Continue');
      expect(state.locale.languageCode, 'en');
    });
  });

  test('ISO language catalog contains 184 unique codes', () {
    expect(appLanguages, hasLength(184));
    expect(appLanguages.map((language) => language.code).toSet(), hasLength(184));
    expect(languageByCode('tg-TJ').nativeName, 'Тоҷикӣ');
  });
}
