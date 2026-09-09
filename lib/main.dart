import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'l10n/l10n_state.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/conversation_service.dart';
import 'services/entitlement_reconciliation_service.dart';
import 'services/online_service.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';
import 'services/stripe_service.dart';
import 'services/translation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BillingService.configureStorekit();

  final settings = SettingsService();
  await settings.init();

  final l10n = L10nState(settings.languageCode);
  L10nStateCode.current = l10n.code;
  l10n.addListener(() => L10nStateCode.current = l10n.code);

  final auth = AuthService(settings);
  final session = SessionService(settings)
    ..refreshVip()
    ..resume();
  final billing = BillingService(settings)
    ..onEntitlementsChanged = session.syncVerifiedEntitlements;
  final entitlementReconciliation = EntitlementReconciliationService(settings)
    ..onEntitlementsChanged = session.syncVerifiedEntitlements;
  billing.onReconciliationRequested = entitlementReconciliation.refresh;
  final translation = TranslationService();
  final online = OnlineService();
  final conversation = ConversationService(translation, online);
  final stripe = StripeService(settings);

  // These services report readiness through ChangeNotifier, so startup remains
  // instant even when a store or network provider is slow.
  unawaited(billing.init());
  unawaited(entitlementReconciliation.start());
  unawaited(translation.init());
  unawaited(online.connect());
  unawaited(stripe.init());

  runApp(
    GloboVerseApp(
      settings: settings,
      l10n: l10n,
      auth: auth,
      session: session,
      billing: billing,
      entitlementReconciliation: entitlementReconciliation,
      translation: translation,
      conversation: conversation,
      online: online,
      stripe: stripe,
    ),
  );
}
