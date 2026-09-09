<p align="center">
  <img src="assets/branding/app_icon.png" width="128" alt="GloboVerse logo">
</p>

<h1 align="center">GloboVerse</h1>
<p align="center"><strong>One world. Every voice.</strong></p>

GloboVerse is a dark, mobile-first Flutter experience for discovering people and community rooms across cultures, translating phrases, and holding timed or VIP conversations.

## What is included

- Polished three-step onboarding and a persistent local profile
- 184-language ISO catalog with safe Flutter locale fallback
- Bundled English, Tajik, Russian, and Uzbek interface copy
- Translation workspace with an optional remote provider and honest offline phrase preview
- Configurable live discovery catalog with rooms, online totals, member presence, lifecycle-aware refresh, ETags, and atomic fallback
- Clearly disclosed sample discovery catalog until a valid remote catalog loads
- Interactive translated conversations with live polling, read receipts, delivery retry, and reporting
- Clearly disclosed on-device `GloboGuide` preview when no conversation API is configured
- Persisted connection timer, one-hour passes, and VIP entitlement state
- App Store / Google Play billing integration points and optional Stripe web checkout
- Connectivity state, dark Material 3 design system, branded native/PWA icons
- Android, iOS, and web runners
- Unit tests and documented quality checks

## Run locally

Requirements: Flutter 3.47 or newer and Dart 3.5 or newer.

```bash
flutter pub get
flutter run
```

Choose a target explicitly when needed:

```bash
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

## Optional runtime configuration

Do not commit credentials. Supply optional build-time configuration with `--dart-define`:

```bash
flutter run \
  --dart-define=TRANSLATION_API_URL=https://api.example.com/translate \
  --dart-define=TRANSLATION_API_KEY=public-or-short-lived-token \
  --dart-define=GLOBOVERSE_DISCOVERY_API_URL=https://api.example.com/v1 \
  --dart-define=GLOBOVERSE_CHAT_API_URL=https://api.example.com/v1 \
  --dart-define=GLOBOVERSE_API_TOKEN=short-lived-access-token \
  --dart-define=STRIPE_CHECKOUT_URL=https://example.com/checkout
```

The translation endpoint receives:

```json
{
  "q": "Hello",
  "source": "auto",
  "target": "tg",
  "format": "text"
}
```

It should return either `{ "translatedText": "Салом" }` or `{ "data": { "translatedText": "Салом" } }`. A detected source can be returned as `detectedLanguage`.

When `GLOBOVERSE_DISCOVERY_API_URL` is set, the app fetches bounded room, member, online-count, and per-member presence data from `GET /discovery` using the contract in [docs/discovery_api.md](docs/discovery_api.md). While online and in the foreground it refreshes once per minute, uses ETags when available, backs off after failures, and refreshes immediately after resume/reconnect; pull-to-refresh remains available. Updates are atomic, so an invalid or failed response retains the last valid catalog. Until one loads—or when the define is omitted—the interface clearly marks bundled rooms and profiles as samples. Sample room/member IDs are never sent to a configured chat backend.

When `GLOBOVERSE_CHAT_API_URL` is omitted, conversations use a clearly labeled, on-device `GloboGuide` preview. No discovered member is impersonated and no chat message leaves the device. When it is set, the app uses the cursor-based REST contract in [docs/conversation_api.md](docs/conversation_api.md), polling only while online and in the foreground. `GLOBOVERSE_API_TOKEN` is optional and sent as a bearer token.

`--dart-define` is not a secret store: its values are compiled into the app. Production builds should obtain short-lived user credentials through a trusted authentication flow rather than embedding long-lived API credentials.

## Billing setup

Create matching products in App Store Connect and Google Play Console:

| Product ID | Type | Entitlement |
| --- | --- | --- |
| `globoverse_hour_pass` | Consumable | 60 connection minutes |
| `globoverse_vip_monthly` | Subscription | 30 days of unlimited time |

The app starts listening to the purchase stream before querying products and completes pending purchases. The current local ledger prevents duplicate delivery during development.

> **Production requirement:** verify App Store and Google Play receipts on a trusted backend before granting time or VIP access. Never trust client-only purchase verification for a production entitlement.

Stripe checkout is opened only when `STRIPE_CHECKOUT_URL` is defined. Secret Stripe keys belong on the checkout backend, never in this Flutter app.

## Project structure

```text
lib/
├── core/               # Theme, formatters, and shared widgets
├── l10n/               # App language state and 184-language catalog
├── models/             # Serializable conversation domain models
├── screens/            # Onboarding, home, translate, connect, profile
├── services/           # Auth, settings, sessions, chat, billing, network, translation
├── app.dart             # Providers, MaterialApp, auth gate
└── main.dart            # Service initialization
```

## Quality checks

```bash
dart format lib test
flutter analyze --fatal-infos
flutter test
```

Persistent settings are convenience data backed by `shared_preferences`; they are not used for passwords or other secrets.
