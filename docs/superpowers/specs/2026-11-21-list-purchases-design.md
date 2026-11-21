# Step 1: List recent Bandcamp purchases — Design

## Goal

A Swift CLI, `bandcamp-sync list`, that prints the user's most recent Bandcamp
purchases. Foundation for later steps (enumerate Music, diff, import, GUI).

## Structure

Swift package (macOS 14+, Swift 6 language mode):

```
Package.swift
Sources/BandcampKit/      Purchase.swift, BandcampClient.swift, Credentials.swift
Sources/bandcamp-sync/    root command + `list` subcommand (swift-argument-parser)
Tests/BandcampKitTests/   JSON fixtures + tests (Swift Testing)
```

`BandcampKit` is a library so later steps and the GUI reuse it. The executable
stays thin: argument parsing and output formatting only.

## Authentication

Bandcamp has no public fan API and its login form has captcha/2FA, so we reuse
the browser session's `identity` cookie.

`Credentials` resolves the cookie in order:

1. `BANDCAMP_IDENTITY` environment variable
2. `~/.config/bandcamp-sync/identity` (contents trimmed of whitespace)

If neither exists, fail with instructions: open bandcamp.com logged in →
browser dev tools → Cookies → copy the value of `identity`.

## BandcampClient

Async, built on URLSession. HTTP transport is injected behind a small protocol
(`func data(for: URLRequest) async throws -> (Data, URLResponse)`) so tests can
stub it. Every request sends `Cookie: identity=<value>`.

- `fanID() async throws -> Int`
  GET `https://bandcamp.com/api/fan/2/collection_summary`, read `fan_id`.
- `purchases(limit: Int) async throws -> [Purchase]`
  POST `https://bandcamp.com/api/fancollection/1/collection_items` with JSON
  body `{"fan_id": <id>, "older_than_token": <token>, "count": <n>}`.
  Initial token is `"<now unix seconds>::a::"`. Follow `last_token` while
  `more_available` is true and fewer than `limit` items are collected.
  Result is sorted by `purchasedAt` descending and truncated to `limit`.

## Purchase model

`Codable`, `Sendable`:

| Field          | Source                                   |
|----------------|------------------------------------------|
| `saleItemID`   | `sale_item_id`                           |
| `itemType`     | `item_type` (`album`, `track`, `package`; unknown values preserved) |
| `artist`       | `band_name`                              |
| `title`        | `item_title`                             |
| `purchasedAt`  | `purchased`, format `dd MMM yyyy HH:mm:ss zzz` (e.g. `21 Nov 2026 10:00:00 GMT`), en_US_POSIX |
| `itemURL`      | `item_url`                               |
| `redownloadURL`| top-level `redownload_urls["p<sale_item_id>"]`, optional |

`redownloadURL` is unused in step 1 but captured for step 4.

## CLI

```
bandcamp-sync list [--limit <n>] [--json]
```

- `--limit` defaults to 10.
- Default output: aligned table with columns Date (`yyyy-MM-dd`), Artist,
  Title, Type.
- `--json`: pretty-printed JSON array of `Purchase` (ISO 8601 dates).

## Errors

Typed `BandcampError`, each mapped to a clear message and non-zero exit:

- `missingCredentials` — with how-to text
- `unauthorized` — non-2xx from collection_summary, or no `fan_id` in response
  ("cookie rejected or expired")
- `http(status:)` — other non-2xx responses
- `decoding` — unexpected response shape
- Network errors surface URLSession's message.

## Testing

- Unit tests with recorded/handcrafted JSON fixtures through the stub transport:
  pagination across multiple pages, stopping at `limit`, stopping when
  `more_available` is false, date parsing, redownload URL lookup, sorting,
  unauthorized and decoding errors, credential resolution order.
- Real-site verification is manual: run `list` with a real cookie. No network
  in tests.

## Out of scope / risks

- Endpoints are unofficial and may change.
- Hidden collection items (separate endpoint) are not listed.
- Wishlist, downloads, Keychain storage, in-app login: later steps.
