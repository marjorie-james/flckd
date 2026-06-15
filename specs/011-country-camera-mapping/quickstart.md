# Quickstart: Country-Wide Camera Mapping

Audience: the **operator** standing up or reconfiguring a flckd deployment. The
configured country drives search, routing, map framing, and camera coverage.

> Resource note: a whole-US build is ~10+ GB of OSM plus the whole-US TIGER bundle
> (~1.8 GB) and a long Nominatim import. Run country builds on a larger/self-hosted
> machine, **not** a laptop or standard CI runner. See `docs/runbooks/geo-stack.md`.

## Set up a deployment (interactive wizard)

```bash
infra/scripts/setup.sh
```

The wizard prompts for scope: enter a **2-letter state** (e.g. `CA`) or **`US`** for the whole
country. It **defaults to `IA`** (Iowa — a cheap, fast single-state dev build). Non-interactive:

```bash
infra/scripts/setup.sh --country us     # whole country
infra/scripts/setup.sh --region CA      # a single state
COUNTRY=us infra/scripts/setup.sh        # whole country (env; an explicit --region wins over this)
```

`setup.sh` writes `infra/.region` + `infra/.env` (the latter selects the backend's
country-vs-state geocoder scope + map framing — turnkey, no manual env edits) and runs the full
build: extract → routing + tiles → DB + seed → geocoder OSM import → TIGER → cameras → manifest.

> The whole-US geocoder OSM import takes **hours**; the wizard waits up to `GEO_GEOCODER_TIMEOUT`
> minutes (default 360 for a country, 35 for a single state).

## Provision a whole country non-interactively (one command)

```bash
COUNTRY=us infra/scripts/build-geo.sh        # default: the whole US
COUNTRY=<iso2> infra/scripts/build-geo.sh    # switch country (FR-012/013)
```

`build-geo.sh` is the canonical **non-interactive** country provisioner: fetch extract →
routing + tiles → seed the data-region → geocoder + whole-country TIGER → import cameras →
manifest. (`setup.sh` is the interactive wizard with the same scope; for CI/artifact-only builds
set `GEO_ARTIFACTS_ONLY=1` to stop after the manifest.)

- Only **US** is populated and validated at launch. An unknown / un-provisioned country code
  **fails fast** with an actionable error (FR-009) — never silently swapped for another country.
- A leftover single-state `infra/.region` makes `build-geo.sh` **refuse** (it would mis-scope a
  state extract) — use `setup.sh --region <state>` for single-state dev builds.
- Switching country is a configuration change plus this one provisioning run; no code changes
  (SC-004). Absent `infra/.env`, the backend defaults to whole-country **US** (FR-002).

## Verify

```bash
# Map frames the whole configured country (FR-007):
curl -s http://localhost:3000/api/v1/coverage/bounds
#   → {"bounds":[[-125.0,24.5],[-66.9,49.5]]}  (US)

# Address search resolves across states and disambiguates by state (FR-003/004):
curl -s "http://localhost:3000/api/v1/geocode/search?q=Springfield,%20IL"
curl -s "http://localhost:3000/api/v1/geocode/search?q=Springfield,%20MO"
#   → different, state-correct results

# Cross-state route (FR-005):
curl -s http://localhost:3000/api/v1/routes -H 'Content-Type: application/json' \
  -d '{"route":{"origin":{"lat":41.5868,"lng":-93.6250},
       "destination":{"lat":39.0997,"lng":-94.5786},"locale":"en"}}'   # Des Moines IA → Kansas City MO

# Honest per-data-region coverage (FR-008): present vs absent + freshness
curl -s "http://localhost:3000/api/v1/coverage?lat=41.59&lng=-93.62"
#   → {"covered":true,"data_freshness_at":"..."}  where data exists
#   → {"covered":false,"data_freshness_at":null}  inside US but no gathered data
```

## Config reference

`setup.sh` writes `infra/.env`; `docker-compose` interpolates it into the backend. Absent
`infra/.env`, the backend defaults to whole-country **US** (FR-002).

| Setting | Where | Default | Purpose |
|---------|-------|---------|---------|
| `GEOCODER_COUNTRY` | `infra/.env` (compose) / `deploy.yml` | `us` | Whole-country scope: geocoder viewbox (from the country bbox) + map framing |
| `GEOCODER_REGION_STATE` | `infra/.env` (single-state dev) | _(unset)_ | Single-state mode: legacy geocoder behavior + state-name label fallback |
| `GEOCODER_VIEWBOX` | `infra/.env` (single-state dev) | _(unset)_ | The state's bbox: geocoder bounded search **and** the initial map framing on that state |
| `COUNTRY` | `infra/.region` / env | `us` | Country for the provisioning scripts (default when unset) |
| `GEO_GEOCODER_TIMEOUT` | env (`build-geo.sh` / `setup.sh`) | 360 (country) / 35 (state) min | Cap on the geocoder OSM-import wait |
| `GEO_ARTIFACTS_ONLY` | env (`build-geo.sh`) | _(off)_ | CI: build extract + routing + tiles + manifest only (no services) |

## Anonymity (unchanged — FR-011)

Provisioning downloads only **public** OSM / Census / Nominatim data. Routing,
geocoding, and tiles continue to run entirely on our own infrastructure — no user
origin/destination/route is ever sent to a third party, at any scale.
