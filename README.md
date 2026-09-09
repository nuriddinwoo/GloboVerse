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
- Persisted connection timer plus journaled, server-verified one-hour and VIP grants
- Revisioned startup/foreground VIP reconciliation, including authoritative expiry and revocation
- Fail-closed App Store / Google Play billing with a configurable authenticated verification boundary
- Connectivity state, dark Material 3 design system, branded native/PWA icons
- Android, iOS, and web runners
- Unit tests and documented quality checks

## Run locally

Requirements: Flutter 3.47 or newer and Dart 3.10 or newer.

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
  --dart-define=GLOBOVERSE_BILLING_API_URL=https://api.example.com/v1 \
  --dart-define=GLOBOVERSE_API_TOKEN=short-lived-access-token
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

When `GLOBOVERSE_CHAT_API_URL` is omitted, conversations use a clearly labeled, on-device `GloboGuide` preview. No discovered member is impersonated and no chat message leaves the device. When it is set, the app uses the cursor-based REST contract in [docs/conversation_api.md](docs/conversation_api.md), polling only while online and in the foreground. `GLOBOVERSE_API_TOKEN` is optional for the previewable discovery/chat adapters but required by the billing verifier and entitlement snapshot client.

`--dart-define` is not a secret store: its values are compiled into the app. Production builds should obtain short-lived user credentials through a trusted authentication flow rather than embedding long-lived API credentials.

## Billing setup

Create matching products in App Store Connect and Google Play Console:

| Product ID | Type | Entitlement |
| --- | --- | --- |
| `globoverse_hour_pass` | Consumable | 60 connection minutes |
| `globoverse_vip_monthly` | Subscription | 30 days of unlimited time |

The app listens to the purchase stream before querying products, but it enables buying and restoration only when `GLOBOVERSE_BILLING_API_URL` identifies a valid HTTPS backend and `GLOBOVERSE_API_TOKEN` supplies a bounded short-lived user credential. It forwards only bounded store server-verification data and untrusted metadata; the backend must verify the receipt with Apple or Google and return an exact, stable grant plus a revisioned account snapshot. A purchase callback, product ID, client transaction ID, or local verification field can never grant time or VIP by itself.

Verified grants use a crash-recoverable journal and stable server verification IDs, so duplicate store delivery cannot add an hour twice. Android consumables are consumed only after a verified or definitively rejected response. Transient and pending checks remain unfinished for retry. An authenticated snapshot is reconciled at startup, after restore, on foreground resume, and periodically; only newer revisions can replace VIP state, including clearing revoked access. See the full request/response, idempotency, migration, and backend validation contract in [docs/billing_api.md](docs/billing_api.md).

The old client-trusting purchase ledger is invalidated by a one-time migration. Hosted Stripe checkout is not surfaced yet: the client can reconcile webhook-authored snapshots, but checkout stays disabled until the deployed backend verifies Stripe webhooks and transactionally updates account revisions. `StripeService` remains only a future HTTPS launcher adapter. Secret Stripe keys and webhook secrets belong on the backend, never in this Flutter app.

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

Persistent settings are convenience data backed by `shared_preferences`; they are not used for passwords, receipts, tokens, or other secrets. The verified-grant journal prevents local replay but does not replace the backend’s authoritative transaction records.
