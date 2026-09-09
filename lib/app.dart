import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'l10n/l10n_state.dart';
import 'screens/home/home_shell.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/online_service.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';
import 'services/stripe_service.dart';
import 'services/translation_service.dart';

class GloboVerseApp extends StatelessWidget {
  const GloboVerseApp({
    super.key,
    required this.settings,
    required this.l10n,
    required this.auth,
    required this.session,
    required this.billing,
    required this.translation,
    required this.online,
    required this.stripe,
  });

  final SettingsService settings;
  final L10nState l10n;
  final AuthService auth;
  final SessionService session;
  final BillingService billing;
  final TranslationService translation;
  final OnlineService online;
  final StripeService stripe;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: l10n),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: billing),
        ChangeNotifierProvider.value(value: translation),
        ChangeNotifierProvider.value(value: online),
        ChangeNotifierProvider.value(value: stripe),
      ],
      child: Consumer<L10nState>(
        builder: (context, l10n, _) {
          return MaterialApp(
            title: 'GloboVerse',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            // App strings can use any language in our catalog. Flutter's own
            // widgets can only load kMaterialSupportedLanguages, so L10nState
            // safely falls back to English for framework strings only.
            locale: l10n.locale,
            supportedLocales: kMaterialSupportedLanguages
                .map((code) => Locale(code))
                .toList(growable: false),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

/// Shows onboarding for guests and the main shell for signed-in users.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return auth.isSignedIn ? const HomeShell() : const OnboardingScreen();
  }
}
