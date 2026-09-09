import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/auth_service.dart';
import 'package:globoverse/services/settings_service.dart';

void main() {
  test(
    'local onboarding signs in and sign out returns to onboarding',
    () async {
      final settings = SettingsService();
      final auth = AuthService(settings);

      expect(auth.isSignedIn, isFalse);
      expect(await auth.completeOnboarding(displayName: 'Amina'), isTrue);
      expect(auth.isSignedIn, isTrue);
      expect(settings.displayName, 'Amina');

      await auth.signOut();
      expect(auth.isSignedIn, isFalse);
      expect(settings.displayName, 'Amina');
    },
  );

  test('short display names are rejected', () async {
    final auth = AuthService(SettingsService());

    expect(await auth.completeOnboarding(displayName: 'A'), isFalse);
    expect(auth.isSignedIn, isFalse);
    expect(auth.error, isNotNull);
  });
}
