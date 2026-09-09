# GloboVerse architecture

## Bootstrap

`main.dart` initializes persistent settings first, then constructs every long-lived service exactly once. Those instances are exposed through `MultiProvider` in `app.dart`. Network, store, and translation initialization is deliberately fire-and-forget so the first frame is not blocked.

## State ownership

- `SettingsService`: device-persisted preferences plus serialized, crash-safe application of server-verified grants and revisioned authoritative VIP snapshots.
- `L10nState`: selected app language and synchronous interface copy.
- `AuthService`: onboarding/auth gate for the local profile. A remote identity adapter can replace its persistence without changing the gate.
- `SessionService`: lifecycle-aware connection countdown and VIP state.
- `BillingService`: store catalog, serialized purchase stream, fail-closed backend verification, and post-verification store completion.
- `EntitlementReconciliationService`: authenticated startup, foreground-resume, and periodic account snapshot refresh with stale-revision protection.
- `TranslationService`: optional concurrent HTTP translations plus an offline phrase preview.
- `ConversationService`: one active translated conversation, cursor-based live polling, read/delivery receipts, retry/report actions, and REST lifecycle ownership. Without a configured backend it talks only to the explicitly labeled on-device `GloboGuide` preview.
- `OnlineService`: connectivity plus a configurable discovery/presence REST catalog. It validates and bounds remote payloads, swaps catalogs atomically, and retains a visibly disclosed sample catalog until the first valid response.
- `StripeService`: dormant HTTPS hosted-checkout launcher; it is not surfaced until the deployed backend can feed verified Stripe webhook updates into account snapshots.

## Locale safety

The app catalog contains every ISO 639-1 language. `L10nState.code` preserves the selected language, while `L10nState.locale` only returns locales supported by Flutter's `GlobalMaterialLocalizations`. Unsupported framework locales fall back to English, preventing delegate lookup failures while leaving the selected app/translation language unchanged.

## Discovery lifecycle

`OnlineService` owns connectivity, app-lifecycle-aware discovery scheduling, aggregate online count, rooms, and member presence. It starts with immutable sample data and marks that state explicitly. With `GLOBOVERSE_DISCOVERY_API_URL` configured, startup and reconnect request `GET /discovery`; foreground operation refreshes every minute, pauses outside the foreground, resumes immediately, and exponentially backs off failed refreshes to 15 minutes. Valid ETags produce conditional requests and safe `304 Not Modified` checks, while abort signals release supported HTTP transports on timeout, backgrounding, disconnection, or disposal. A candidate response is size-limited, normalized, de-duplicated, and parsed into temporary bounded collections; only a candidate whose required sections validate replaces the current catalog. Errors preserve either the last valid remote snapshot or the disclosed sample snapshot. Home and Connect render loading, stale/error, preview, and authentic empty states and support pull-to-refresh. The endpoint contract is documented in [`discovery_api.md`](discovery_api.md).

Discovery notifications and connectivity changes share one notifier. `ConversationService` tracks the previous connectivity value so a catalog refresh does not trigger chat reconnect/read work. While the sample catalog is active, both the UI and conversation boundary convert sample-card actions to a generic match request; sample IDs cannot leave the client as `roomId` or `peerId`.

## Trusted billing lifecycle

`BillingService` subscribes to store updates before querying products, but purchase and restore controls fail closed unless `GLOBOVERSE_BILLING_API_URL` and a bounded user bearer token configure an authenticated HTTPS `PurchaseVerifier`. Purchased/restored events are serialized and forwarded as bounded server verification data. Only an exact verified grant plus an authoritative account snapshot returned by that backend can reach `SettingsService`; client product IDs, transaction IDs, dates, statuses, and local receipt fields never call `SessionService` or mutate VIP state directly.

A stable server `verificationId` drives a write-ahead grant journal. Before applying a verified grant, `SessionService` durably flushes locally consumed seconds so an in-flight countdown cannot be overwritten by a stale balance. The journal then persists the exact target time/VIP state and account revision before recording delivery. Afterward, `SessionService` merges only the exact newly applied trusted delta into its live balance—preserving usage during the journal write—and persists that merged balance before store completion. Failure at either session boundary leaves the event unfinished for retry; duplicate delivery reports that no new delta was applied and cannot add the hour twice. The app manually consumes Android hour passes only after this sequence or a definitive rejection; generic canceled/error events are completed without consumable delivery, and transient/pending verification remains unfinished for retry.

`EntitlementReconciliationService` requests the authenticated account snapshot at startup, every foreground resume, and every 15 minutes while foregrounded. `SettingsService` serializes this with session writes and purchase grants, journals it independently, applies only increasing revisions, rejects conflicting equal revisions, and replaces VIP exactly so a `null` value revokes local access. Network or malformed-response failures grant nothing and retain only the last verified deadline. The request/response and backend rules are documented in [`billing_api.md`](billing_api.md).

The first hardened startup clears the legacy client purchase ledger, removes client-derived VIP, and caps old connection time at the original free allocation. Billing UI states distinguish unavailable products, store pending, server verification, backend pending, fail-closed configuration, definitive rejection, retryable verification error, and verified success. Hosted Stripe checkout remains hidden: launching a URL cannot deliver access, although the client snapshot path can observe future backend webhook updates.

## Conversation lifecycle

`ConnectScreen` first claims time from `SessionService`, then asks `ConversationService` to create a remote session (or local preview). The live sheet observes both services: messages cannot be composed before the conversation is active, while session expiry closes the sheet. Closing, a successful report, and expiry end the conversation and pause the entitlement timer; startup failure also pauses the timer. Countdown restoration charges only the interval after a stored VIP deadline, and authoritative VIP refreshes preserve locally elapsed but not-yet-persisted seconds. A generation token prevents late send, poll, read-acknowledgement, translation, or preview responses from mutating a replaced session.

Remote sessions poll from an opaque cursor every four seconds. Polling stops offline and outside the foreground, resumes immediately after connectivity/lifecycle recovery, and exponentially backs off to 30 seconds after failures. Incoming IDs are de-duplicated, read acknowledgements are batched, and receipt progression is monotonic.

`ConversationMessage` is immutable and serializable. Outgoing messages move through `sending`, `sent`, `delivered`, `read`, or `failed`; failed messages retain their ID and text for explicit idempotent retry. Remote response objects are bounded and validated before they can mutate UI state. The current REST request/response schema is documented in [`conversation_api.md`](conversation_api.md).

## Production adapters

The UI and state contracts are ready for backend adapters. Before release:

1. Replace the local auth profile with the chosen identity provider.
2. Implement the authenticated discovery and conversation contracts, backed by consent-aware presence; move to WebSockets later if lower latency is required.
3. Deploy the documented billing verifier/snapshot endpoints with authenticated Apple/Google checks, durable transaction idempotency, monotonic account revisions, revocation handling, and account-level entitlement records.
4. Use short-lived translation credentials or proxy translation through the backend.
5. Keep Stripe checkout hidden until verified webhooks transactionally update the authenticated snapshots already consumed by the client.
