# Trusted billing verification API

GloboVerse does not grant connection time or VIP access from `PurchaseDetails.productID`, `purchaseID`, transaction dates, purchase status, or local verification data. Store purchases are enabled only when the build defines a trusted HTTPS verification service:

```bash
--dart-define=GLOBOVERSE_BILLING_API_URL=https://api.example.com/v1
--dart-define=GLOBOVERSE_API_TOKEN=short-lived-user-access-token
```

The base URL must be absolute HTTPS with no embedded credentials, query, or fragment. The bearer token is required and must represent the signed-in user; a permanent server secret must never be compiled into the Flutter application. Builds without both a valid endpoint and a nonempty, control-character-free token fail closed. Requests do not follow redirects, time out after 15 seconds with an abort signal, bound submitted store data to 1 MiB, and bound responses to 64 KiB.

When `GLOBOVERSE_BILLING_API_URL` or `GLOBOVERSE_API_TOKEN` is absent or invalid, store products and restore actions remain disabled and the UI says that secure verification is not configured. This fail-closed behavior prevents a store callback from becoming an entitlement by itself.

For Flutter web, the backend must allow only deployed GloboVerse origins and the required `GET`/`POST`, `Authorization`, `Content-Type`, `Accept`, `Cache-Control`, and `Idempotency-Key` CORS fields. Do not combine credentialed billing responses with a wildcard origin.

## Verify a store purchase

```http
POST /v1/billing/verify
Authorization: Bearer <short-lived-user-access-token>
Accept: application/json
Content-Type: application/json
Idempotency-Key: GPA.1234-5678-9012-34567
```

```json
{
  "productId": "globoverse_hour_pass",
  "purchaseId": "GPA.1234-5678-9012-34567",
  "transactionDate": "1788912000000",
  "source": "google_play",
  "verificationData": "store-server-verification-data",
  "isRestore": false
}
```

Only `verificationData` from the plugin's `serverVerificationData` field is intended for receipt verification. The other fields and the `Idempotency-Key` are untrusted routing/idempotency hints. The backend must derive authority from Apple App Store or Google Play verification, not from any client assertion.

Before returning a grant, the backend must:

1. Authenticate the GloboVerse user and bind the verified transaction to that account.
2. Validate the receipt or purchase token directly with the correct store environment.
3. Validate the app bundle/package, product, transaction ownership, payment state, acknowledgement/consumption state, and subscription expiry or revocation state.
4. Reject replay against another account and enforce one grant per underlying store transaction.
5. Persist the grant transactionally before responding and return the same stable `verificationId` on every retry of the same transaction.
6. Calculate the entitlement server-side. Never echo a client-requested amount or client-calculated VIP duration.
7. Rate-limit by account/device and redact bearer tokens, receipts, purchase tokens, and full response bodies from logs and error telemetry.

### Verified one-hour pass

```json
{
  "status": "verified",
  "verificationId": "google:GPA.1234-5678-9012-34567",
  "productId": "globoverse_hour_pass",
  "entitlement": {
    "type": "session_time",
    "seconds": 3600
  },
  "snapshot": {
    "revision": 1042,
    "generatedAt": "2026-09-09T12:00:00.000Z",
    "vipUntil": null
  }
}
```

The client accepts exactly 3,600 seconds for `globoverse_hour_pass`.

### Verified monthly VIP

```json
{
  "status": "verified",
  "verificationId": "apple:2000000123456789",
  "productId": "globoverse_vip_monthly",
  "entitlement": {
    "type": "vip",
    "expiresAt": "2026-10-09T12:00:00.000Z"
  },
  "snapshot": {
    "revision": 1043,
    "generatedAt": "2026-09-09T12:00:00.000Z",
    "vipUntil": "2026-10-09T12:00:00.000Z"
  }
}
```

Every verified response must include the account's current authoritative snapshot. Retries preserve the grant and `verificationId`, but must attach a freshly generated snapshot rather than replaying a stale cached response. `revision` is a positive, monotonically increasing, JavaScript-safe integer; `generatedAt` and a non-null `vipUntil` are strict UTC timestamps with second or millisecond precision. The client rejects snapshots over one hour old or over five minutes ahead of its clock. A VIP grant's `expiresAt` must exactly equal the snapshot's `vipUntil`. The expiry must be in the future and no more than 62 days ahead. It comes from trusted subscription state; the client no longer adds 30 days based on a purchase callback.

### Pending or rejected

```json
{ "status": "pending" }
```

```json
{ "status": "rejected" }
```

`pending` means no entitlement has been granted and the transaction should be retried later. `rejected` is a definitive verification decision and also grants nothing. Unknown status values, mismatched product IDs, malformed grant IDs, wrong entitlement types or amounts, invalid expiry dates, oversized bodies, non-`2xx` responses, network failures, and timeouts all fail closed.

## Reconcile authoritative entitlements

```http
GET /v1/billing/entitlements
Authorization: Bearer <short-lived-user-access-token>
Accept: application/json
Cache-Control: no-store
```

```json
{
  "status": "ok",
  "snapshot": {
    "revision": 1044,
    "generatedAt": "2026-09-09T12:15:00.000Z",
    "vipUntil": null
  }
}
```

The backend derives this snapshot only from authenticated account records, current Apple/Google subscription status, and verified Stripe webhook state. It must never derive it from client preferences or a checkout redirect. A `null` `vipUntil` is authoritative revocation or absence of VIP. Each account-state mutation increments `revision`; the same revision must always describe the same VIP state.

The app fetches this endpoint at startup, after an explicit store restore, on foreground resume, and every 15 minutes while foregrounded. It also receives the same snapshot atomically with every verified store grant. Newer revisions replace local VIP state exactly, including clearing it; stale revisions cannot roll state back, and conflicting data at the same revision is rejected. Reconciliation itself uses a write-ahead journal, so expiry or revocation survives process termination during persistence. If refresh fails, no new access is inferred: the app retries later and local VIP still expires at its last verified deadline.

One-hour passes remain backend-verified, transaction-idempotent grants whose countdown is consumed on this installation. Cross-device transfer of already-consumed consumables requires backend-mediated session metering and is intentionally not claimed by this contract.

## Idempotency and store completion

Purchase updates and settings entitlement writes are serialized. After a verified response, `SettingsService` writes a recovery journal containing the stable server `verificationId`, authoritative snapshot revision, and exact target local state; it persists that state before recording the ID as applied. Re-delivery of the same verified ID cannot add another hour, while a newer attached snapshot can still revoke or refresh VIP. A journal left by an interrupted write is completed on the next startup.

Android consumables are purchased with automatic consumption disabled. The UI disables another hour pass when the bounded local timer cannot hold the full 3,600-second grant; if such a transaction is nevertheless delivered externally, it remains unfinished until capacity is available rather than silently discarding paid time. Consumables are consumed only after a complete verified grant or a definitive backend rejection. Other completed transactions are acknowledged/finished after the same decision. A pending response or transient verification failure is not finished, allowing the store event to be retried rather than silently losing a paid entitlement.

The backend remains the source of truth and must implement its own transaction-level idempotency. The local journal is crash/re-delivery protection, not receipt validation and not a substitute for server records.

## Legacy migration and UI behavior

The one-time billing security migration removes the old client purchase ledger, clears client-derived VIP, and caps pre-verification connection time at the original 20-minute free allocation. New purchase UI states distinguish unavailable store products, store pending, server verification, backend pending, verification unavailable, definitive rejection, retryable verification error, and verified success. Missing store prices appear as an em dash rather than a fabricated fallback price. A failed account refresh is shown separately with an explicit retry action and never claims that access changed. None of the non-verified states claims that access was added.

## Hosted Stripe checkout

`StripeService` remains a hardened HTTPS launcher adapter, but hosted checkout is deliberately not surfaced in the billing sheet. A checkout link or success redirect alone cannot update entitlements safely. The client reconciliation path is ready to observe a newer webhook-authored snapshot, but checkout must remain disabled until the deployed backend authenticates checkout sessions, verifies Stripe webhook signatures idempotently, updates the account revision transactionally, and serves that state from `/billing/entitlements`. Secret Stripe keys and webhook secrets belong only on the backend.
