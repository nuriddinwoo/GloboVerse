# GloboVerse architecture

## Bootstrap

`main.dart` initializes persistent settings first, then constructs every long-lived service exactly once. Those instances are exposed through `MultiProvider` in `app.dart`. Network, store, and translation initialization is deliberately fire-and-forget so the first frame is not blocked.

## State ownership

- `SettingsService`: device-persisted preferences and local entitlement metadata.
- `L10nState`: selected app language and synchronous interface copy.
- `AuthService`: onboarding/auth gate for the local profile. A remote identity adapter can replace its persistence without changing the gate.
- `SessionService`: lifecycle-aware connection countdown and VIP state.
- `BillingService`: store catalog, purchase stream, and entitlement delivery.
- `TranslationService`: optional HTTP provider plus an offline phrase preview.
- `OnlineService`: connectivity and discover-domain data. Replace the static room/member repository when a backend is available.
- `StripeService`: external hosted-checkout launcher; no Stripe secret is stored in the client.

## Locale safety

The app catalog contains every ISO 639-1 language. `L10nState.code` preserves the selected language, while `L10nState.locale` only returns locales supported by Flutter's `GlobalMaterialLocalizations`. Unsupported framework locales fall back to English, preventing delegate lookup failures while leaving the selected app/translation language unchanged.

## Production adapters

The UI and state contracts are ready for backend adapters. Before release:

1. Replace the local auth profile with the chosen identity provider.
2. Return rooms, presence, and sessions from an authenticated API/WebSocket.
3. Verify store receipts server-side and return signed entitlements.
4. Use short-lived translation credentials or proxy translation through the backend.
5. Handle Stripe checkout completion with a verified webhook and entitlement refresh.
