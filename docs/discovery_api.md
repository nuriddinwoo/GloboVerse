# Discovery REST API

`OnlineService` uses this contract when the Flutter build defines a non-empty `GLOBOVERSE_DISCOVERY_API_URL`. The examples below assume the base URL is `https://api.example.com/v1`.

The optional `GLOBOVERSE_API_TOKEN` is sent as a bearer token:

```http
Authorization: Bearer <token>
```

The client requests JSON, accepts any `2xx` status, does not follow redirects, times out after 15 seconds, and stops reading response bodies larger than 1 MiB. The configured base URL must be an absolute HTTP(S) URL without embedded credentials, a query, or a fragment.

> `--dart-define` values are compiled into the application. A permanent backend secret must never be shipped this way. Use the token only for development or supply a short-lived user credential through a trusted authentication flow.

## Fetch discovery and presence

```http
GET /v1/discovery
Accept: application/json
```

A successful response has this shape:

```json
{
  "onlineCount": 284,
  "rooms": [
    {
      "id": "central-asia",
      "title": "Central Asia lounge",
      "subtitle": "Culture and travel",
      "emoji": "🏔️",
      "memberCount": 31,
      "languageCodes": ["tg", "uz", "ru"],
      "accentColor": "#5CC8FF"
    }
  ],
  "members": [
    {
      "id": "member-42",
      "name": "Amina",
      "city": "Dushanbe",
      "country": "Tajikistan",
      "languageCode": "tg",
      "avatarSeed": 42,
      "isVip": true,
      "isOnline": true
    }
  ]
}
```

`onlineCount`, `rooms`, and `members` are required. Empty room and member arrays are valid and produce explicit empty states in the app.

## Validation and bounds

The Flutter client treats every field as untrusted and validates the complete candidate catalog before replacing its current state. Display strings containing ASCII control characters or Unicode bidirectional override/isolate controls are rejected.

| Value | Client rule |
| --- | --- |
| `onlineCount` | Integer from 0 through 10,000,000 |
| Rooms | At most 50 accepted entries; duplicate IDs after the first are ignored |
| Members | At most 100 accepted entries; duplicate IDs after the first are ignored |
| IDs | 1–100 characters matching `^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$` |
| Room title | Non-empty, no control characters, at most 120 code units |
| Room subtitle | Non-empty, no control characters, at most 240 code units |
| Emoji | Non-empty, no control characters, at most 16 code units |
| Room member count | Integer from 0 through 10,000,000 |
| Room languages | 1–10 unique, valid language tags |
| Member name | Non-empty, no control characters, at most 100 code units |
| Member city/country | Non-empty, no control characters, at most 120 code units each |
| Member language | A normalized language tag such as `tg`, `en`, or `pt-br` |
| `isOnline` | Required Boolean used for per-member presence |
| `isVip` | Optional Boolean; any missing or non-Boolean value becomes `false` |
| `avatarSeed` | Optional non-negative integer, capped at 1,000,000,000; otherwise derived from the member ID |
| `accentColor` | RGB/ARGB integer or six/eight-digit hexadecimal string |

Invalid individual entries are skipped. If a non-empty room or member array contains no valid entries, the whole response is rejected rather than being presented as an authentic empty catalog. Collection limits and the response-size limit bound parsing work.

The service parses `onlineCount`, rooms, members, presence, and colors into temporary values first. It commits them together only after all required sections pass validation. A malformed or failed refresh therefore cannot mix a new count with old rooms or partially replace member presence.

## Refresh and fallback behavior

- The app begins with a bundled room/profile sample catalog that is visibly labeled as a preview, not as live membership.
- A valid remote response atomically replaces that catalog, records its refresh time, and remains the in-memory fallback for the current app process.
- Startup, reconnect, and pull-to-refresh can request the endpoint. Duplicate refresh requests are ignored while one is active.
- A timeout, network error, non-`2xx` status, oversized body, or invalid payload retains the last valid catalog and exposes a localized retry notice.
- If no valid remote catalog has ever loaded, a failed refresh retains the disclosed sample catalog.
- Connectivity loss changes the displayed live count to zero without deleting the last valid catalog.

The bundled sample room and profile IDs are presentation-only. `ConversationService` strips room/member targets while the sample catalog is active, so a configured chat backend receives only a generic session match request and never receives a sample identity.

## Backend guidance

Authenticate the caller, authorize catalog visibility, rate-limit the endpoint, and calculate presence on trusted infrastructure. Return only profiles that consent to discovery. Do not expose private location or activity data. Web deployments must allow the app’s exact HTTPS origin through a narrow CORS policy and should cache or revalidate the catalog according to the desired presence freshness.
