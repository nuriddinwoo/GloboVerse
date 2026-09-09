# Conversation REST API

`ConversationService` uses this contract when the Flutter build defines a non-empty `GLOBOVERSE_CHAT_API_URL`. The examples below assume the base URL is `https://api.example.com/v1`.

The optional `GLOBOVERSE_API_TOKEN` is sent on every request as:

```http
Authorization: Bearer <token>
```

Requests with bodies use `application/json`, and the client asks for JSON responses. Any `2xx` status is accepted. Conversation requests have a 20-second timeout, best-effort session deletion has an 8-second timeout, and malformed required success payloads are treated as failures.

> `--dart-define` values are compiled into the application. Use the token define only for development or a short-lived credential; do not ship a permanent backend secret in a client build.

## Create a session

```http
POST /v1/sessions
```

```json
{
  "sourceLanguage": "tg",
  "targetLanguage": "en",
  "roomId": "central-asia"
}
```

`roomId` and `peerId` are optional selection hints. The response must include a non-empty string in `id` or `sessionId`. Peer metadata may be nested under `peer` or returned as `peerName`.

```json
{
  "id": "session-123",
  "peer": {
    "id": "member-42",
    "name": "Amina"
  }
}
```

If no valid peer name is returned, the client retains the selected member/room label or displays its localized generic conversation label.

## Send a message

```http
POST /v1/sessions/session-123/messages
```

```json
{
  "id": "local-1725897600000-1",
  "text": "Салом",
  "translatedText": "Hello",
  "sourceLanguage": "tg",
  "targetLanguage": "en",
  "timestamp": "2026-09-09T12:00:00.000Z"
}
```

The Flutter client translates outgoing text before submitting it. Text is trimmed and limited to 600 Unicode code units by the current UI.

The server can return either one message:

```json
{
  "message": {
    "id": "message-456",
    "sender": "peer",
    "text": "Hello",
    "translatedText": "Салом",
    "sourceLanguage": "en",
    "targetLanguage": "tg",
    "timestamp": "2026-09-09T12:00:03.000Z",
    "deliveryState": "sent"
  }
}
```

or a batch:

```json
{
  "messages": [
    {
      "id": "message-456",
      "sender": "peer",
      "text": "Hello",
      "translatedText": "Салом",
      "sourceLanguage": "en",
      "targetLanguage": "tg",
      "timestamp": "2026-09-09T12:00:03.000Z"
    }
  ]
}
```

Accepted `sender` values are `me`, `peer`, and `system`. Accepted `deliveryState` values are `sending`, `sent`, and `failed`. Unknown values use safe client defaults. Entries without a non-empty `id` and `text`, invalid language codes, text fields over 4,000 code units, or timestamps more than one day ahead or one year behind the device clock are ignored.

The submitted outgoing message remains the client's local source of truth. A response should therefore contain only newly received messages, not an echo of the outgoing object. If an incoming message omits `translatedText`, the client asks its configured translation provider (or honest offline phrase preview) to fill it before display. Servers can return at most 50 usable messages per response; additional entries are ignored.

The current REST adapter ingests messages returned by session creation and message submission; it does not yet open a polling or WebSocket channel. A production realtime adapter can extend `ConversationService` without changing the sheet's message model.

## Report a conversation

```http
POST /v1/sessions/session-123/reports
```

```json
{
  "reason": "harassment",
  "reportedAt": "2026-09-09T12:05:00.000Z"
}
```

Current reasons are `harassment`, `spam`, `unsafe_content`, and `other`. A successful report also ends the local conversation UI. The backend should preserve the relevant moderation evidence according to its privacy and retention policy; the Flutter client does not upload extra transcript data in this request.

In on-device `GloboGuide` preview mode, the same control records only an ephemeral preview-feedback flag and is explicitly acknowledged as local feedback; no report is claimed to have reached a server.

## End a session

```http
DELETE /v1/sessions/session-123
```

This request is best effort. The client clears its active conversation even when the delete fails, so the backend should independently expire abandoned sessions.

## Error and retry behavior

- Non-`2xx`, timeout, network, or malformed responses are failures.
- A failed outgoing message stays visible with `failed` state and can be retried explicitly.
- Retrying reuses the same local message ID so the backend can make message submission idempotent.
- Late responses from a session that has ended are discarded by the client.
- Starting a new session always ends local ownership of the previous one.

For production, authenticate every session, authorize room/member access server-side, rate-limit writes, sanitize moderation fields, and use idempotency keyed by the client message ID. Web deployments must also allow the app’s HTTPS origin through an appropriately narrow CORS policy.
