import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/core/utils/formatters.dart';

void main() {
  group('formatDuration', () {
    test('formats minute and hour durations', () {
      expect(formatDuration(const Duration(seconds: 65)), '01:05');
      expect(formatDuration(const Duration(hours: 2, minutes: 3, seconds: 4)), '02:03:04');
    });

    test('never displays a negative duration', () {
      expect(formatDuration(const Duration(seconds: -12)), '00:00');
    });
  });

  group('initialsFor', () {
    test('creates one and two-word initials', () {
      expect(initialsFor('Amina'), 'AM');
      expect(initialsFor('Amina Karimova'), 'AK');
      expect(initialsFor('  '), 'GV');
    });
  });
}
