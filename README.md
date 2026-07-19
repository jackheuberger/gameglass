# Gameglass

**An external source of truth for Xbox Cloud Gaming streamability.**

Gameglass shows, for every cloud-streamable title, which Xbox Game Pass tier can
stream it — **included** with a subscription, **purchase-required**, or
**unavailable** — and publishes a static verify API for any title. All data is
derived from **anonymous, public** Xbox catalog endpoints (no Xbox login / xuid).

Gameglass is an independent, unofficial project and is not affiliated with,
endorsed by, or sponsored by Microsoft. Xbox, Xbox Cloud Gaming, and Xbox Game
Pass are trademarks of Microsoft. This project uses publicly available catalog
information and does not provide access to Xbox services or game content.

There is no server and no database: a scanner commits JSON snapshots to this
repository, and a static site is rendered from them. The git history of
`data/` **is** the audit trail — `git log -p data/games.json` shows every
catalog change Gameglass ever observed.

## How it works

1. **Enumerate** the full cloud catalog via the "All games" SIGL collection that
   backs `play.xbox.com/gallery/all-games` (`catalog.gamepass.com/sigls/v2`),
   unioned with every subscription plan.
2. **Enrich** each title via `catalog.gamepass.com/v3/products` (Sapphire
   hydration) for its xCloud programs, Game Pass metadata, price, and
   `XCloudTitleId`.
3. **Classify** each (game, tier) pair by joining the streaming *programs*
   (which tiers *can* stream with an entitlement) with *pass metadata* (which
   tiers *include* it for free). Neither signal alone is sufficient.
4. **Commit** the snapshot (`data/games.json`), the change log
   (`data/changes.jsonl`), and the scan audit log (`data/runs.jsonl`), then
   render the static site.

## Running

Requires Elixir 1.15+; CI currently uses Elixir 1.17 and Erlang/OTP 27.

* `mix deps.get` — install deps
* `mix gameglass.scan` — crawl the live endpoints (~3,000 titles, ~1 minute)
  and update `data/`
* `mix gameglass.build_site` — render the site into `_site/`
* `mix gameglass.serve` — preview `_site/` at
  [`localhost:4000`](http://localhost:4000)

In CI, a scheduled GitHub Actions workflow
([`.github/workflows/scan.yml`](.github/workflows/scan.yml)) scans every few
hours, commits `data/` when anything changed, and deploys `_site/` to GitHub
Pages. `workflow_dispatch` triggers an on-demand scan.

## Publishing

Before the first deploy, set **Settings → Pages → Source** to **GitHub Actions**
in the GitHub repository. Then run the **Scan and deploy** workflow manually;
future scans run every six hours. If `main` has branch protection, allow the
GitHub Actions workflow to push the automated `data/` commits, or change that
step to open a pull request instead.

## API

Public, read-only, fully static — one pre-resolved JSON file per lookup key:

```
GET /api/by-product/9NLRT31Z4RWM.json  # by store productId/BigId
GET /api/by-xcloud/TUNIC.json          # by XCloudTitleId
GET /api/by-xbox/1848191014.json       # by xboxTitleId
GET /api/games.json                    # the full listing + scan metadata
```

An unknown id is the host's plain 404. Response:

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
      "links": {
        "store": "https://www.xbox.com/games/store/tunic/9NLRT31Z4RWM",
        "play_new": "https://play.xbox.com/products/9NLRT31Z4RWM/tunic",
        "play_legacy": "https://www.xbox.com/play/games/tunic/9NLRT31Z4RWM"
      },
      "last_verified_at": "2026-06-23T01:33:25Z"
    }
  ]
}
```

## Tests

```
mix test
```
