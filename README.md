# Gameglass

**An external source of truth for Xbox Cloud Gaming streamability.**

Gameglass shows, for every cloud-streamable title, which Xbox Game Pass tier can
stream it — **included** with a subscription, **purchase-required**, or
**unavailable** — and exposes a public API to verify any title. All data is
derived from **anonymous, public** Xbox catalog endpoints (no Xbox login / xuid).

## How it works

1. **Enumerate** the full cloud catalog via the "All games" SIGL collection that
   backs `play.xbox.com/gallery/all-games` (`catalog.gamepass.com/sigls/v2`).
2. **Enrich** each title via `catalog.gamepass.com/v3/products` (Sapphire
   hydration) for its xCloud programs, Game Pass metadata, price, and
   `XCloudTitleId`.
3. **Classify** each (game, tier) pair by joining the streaming *programs*
   (which tiers *can* stream with an entitlement) with *pass metadata* (which
   tiers *include* it for free). Neither signal alone is sufficient.

See [`PLAN.md`](PLAN.md) for the full design and the data-source reverse
engineering.

## Running

* `mix setup` — install deps, create the SQLite database, run migrations
* `mix phx.server` — start the server, then visit
  [`localhost:4000`](http://localhost:4000)
* Click **Refresh** in the UI (or run `Gameglass.Ingest.refresh()` in `iex`) to
  populate the catalog from the live endpoints (~3,000 titles, ~1 minute).

The database is SQLite (`gameglass_dev.db`).

## API

Public, read-only. Resolves base games, editions, and bundles.

```
GET /api/games/:product_id            # by store productId/BigId
GET /api/games?xcloudTitleId=TUNIC    # by XCloudTitleId
GET /api/games?xboxTitleId=1848191014 # by xboxTitleId
```

Response:

```json
{
  "streamable": true,
  "count": 1,
  "games": [
    {
      "xcloud_title_id": "TUNIC",
      "product_id": "9NLRT31Z4RWM",
      "title": "TUNIC",
      "streamable": true,
      "is_free": false,
      "tiers": {
        "starter": "included",
        "essential": "included",
        "premium": "included",
        "ultimate": "included"
      },
      "price": { "value": 29.99, "formatted": "$29.99", "currency": "USD" },
      "last_verified_at": "2026-06-23T01:33:25Z"
    }
  ]
}
```

## Tests

```
mix test
```
