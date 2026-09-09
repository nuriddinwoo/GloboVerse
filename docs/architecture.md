# GloboVerse architecture

## Bootstrap

`main.dart` initializes persistent settings first, then constructs every long-lived service exactly once. Those instances are exposed through `MultiProvider` in `app.dart`. Network, store, and translation initialization is deliberately fire-and-forget so the first frame is not blocked.

## State ownership

- `SettingsService`: device-persisted preferences and local entitlement metadata.
- `L10nState`: selected app language and synchronous interface copy.
- `AuthService`: onboarding/auth gate for the local profile. A remote identity adapter can replace its persistence without changing the gate.
- `SessionService`: lifecycle-aware connection countdown and VIP state.
- `BillingService`: store catalog, purchase stream, and entitlement delivery.
- `TranslationService`: optional concurrent HTTP translations plus an offline phrase preview.
- `ConversationService`: one active translated conversation, cursor-based live polling, read/delivery receipts, retry/report actions, and REST lifecycle ownership. Without a configured backend it talks only to the explicitly labeled on-device `GloboGuide` preview.
- `OnlineService`: connectivity plus a configurable discovery/presence REST catalog. It validates and bounds remote payloads, swaps catalogs atomically, and retains a visibly disclosed sample catalog until the first valid response.
- `StripeService`: external hosted-checkout launcher; no Stripe secret is stored in the client.

## Locale safety

The app catalog contains every ISO 639-1 language. `L10nState.code` preserves the selected language, while `L10nState.locale` only returns locales supported by Flutter's `GlobalMaterialLocalizations`. Unsupported framework locales fall back to English, preventing delegate lookup failures while leaving the selected app/translation language unchanged.

## Discovery lifecycle

`OnlineService` owns connectivity, app-lifecycle-aware discovery scheduling, aggregate online count, rooms, and member presence. It starts with immutable sample data and marks that state explicitly. With `GLOBOVERSE_DISCOVERY_API_URL` configured, startup and reconnect request `GET /discovery`; foreground operation refreshes every minute, pauses outside the foreground, resumes immediately, and exponentially backs off failed refreshes to 15 minutes. Valid ETags produce conditional requests and safe `304 Not Modified` checks, while abort signals release supported HTTP transports on timeout, backgrounding, disconnection, or disposal. A candidate response is size-limited, normalized, de-duplicated, and parsed into temporary bounded collections; only a candidate whose required sections validate replaces the current catalog. Errors preserve either the last valid remote snapshot or the disclosed sample snapshot. Home and Connect render loading, stale/error, preview, and authentic empty states and support pull-to-refresh. The endpoint contract is documented in [`discovery_api.md`](discovery_api.md).

Discovery notifications and connectivity changes share one notifier. `ConversationService` tracks the previous connectivity value so a catalog refresh does not trigger chat reconnect/read work. While the sample catalog is active, both the UI and conversation boundary convert sample-card actions to a generic match request; sample IDs cannot leave the client as `roomId` or `peerId`.

## Conversation lifecycle

`ConnectScreen` first claims time from `SessionService`, then asks `ConversationService` to create a remote session (or local preview). The live sheet observes both services: messages cannot be composed before the conversation is active, while session expiry closes the sheet. Closing, a successful report, and expiry end the conversation and pause the entitlement timer; startup failure also pauses the timer. A generation token prevents late send, poll, read-acknowledgement, translation, or preview responses from mutating a replaced session.

Remote sessions poll from an opaque cursor every four seconds. Polling stops offline and outside the foreground, resumes immediately after connectivity/lifecycle recovery, and exponentially backs off to 30 seconds after failures. Incoming IDs are de-duplicated, read acknowledgements are batched, and receipt progression is monotonic.

`ConversationMessage` is immutable and serializable. Outgoing messages move through `sending`, `sent`, `delivered`, `read`, or `failed`; failed messages retain their ID and text for explicit idempotent retry. Remote response objects are bounded and validated before they can mutate UI state. The current REST request/response schema is documented in [`conversation_api.md`](conversation_api.md).

## Production adapters

The UI and state contracts are ready for backend adapters. Before release:

1. Replace the local auth profile with the chosen identity provider.
2. Implement the authenticated discovery and conversation contracts, backed by consent-aware presence; move to WebSockets later if lower latency is required.
3. Verify store receipts server-side and return signed entitlements.
4. Use short-lived translation credentials or proxy translation through the backend.
5. Handle Stripe checkout completion with a verified webhook and entitlement refresh.
