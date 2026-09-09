import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/session_service.dart';
import 'package:globoverse/services/settings_service.dart';

void main() {
  testWidgets('active sessions count down and pause cleanly', (_) async {
    final settings = SettingsService();
    var now = DateTime.utc(2026, 9, 9, 12);
    final session = SessionService(settings, now: () => now);
    final initialSeconds = session.remaining.inSeconds;

    expect(session.start(), isTrue);
    now = now.add(const Duration(seconds: 2));
    session.pause();

    expect(session.remaining.inSeconds, initialSeconds - 2);
    expect(session.isActive, isFalse);
    session.dispose();
  });

  testWidgets('an exhausted session cannot start again', (_) async {
    final settings = SettingsService();
    await settings.setRemainingSeconds(1);
    var now = DateTime.utc(2026, 9, 9, 12);
    final session = SessionService(settings, now: () => now);

    expect(session.start(), isTrue);
    now = now.add(const Duration(seconds: 2));
    session.pause();

    expect(session.remaining, Duration.zero);
    expect(session.canStart, isFalse);
    session.dispose();
  });

  testWidgets('an hour pass extends available connection time', (_) async {
    final settings = SettingsService();
    final session = SessionService(settings);
    final initialSeconds = session.remaining.inSeconds;

    session.extendBy(const Duration(hours: 1));

    expect(session.remaining.inSeconds, initialSeconds + 3600);
    session.dispose();
  });
}
