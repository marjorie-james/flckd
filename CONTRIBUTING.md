# Contributing to flckd

Thanks for your interest in contributing! flckd is an anonymous, camera-avoiding route
planner. This guide covers how to get set up, the bar for changes, and the licensing you
agree to when you contribute.

By participating you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Licensing of contributions (please read)

flckd is **dual-licensed by artifact**:

- **Code** is licensed under [AGPL-3.0-only](LICENSE). If you run a modified version as a
  network service, you must offer your source to its users.
- **Data** (the camera dataset, derived from OpenStreetMap) is licensed under
  [ODbL-1.0](https://opendatacommons.org/licenses/odbl/1-0/) — see
  [docs/adr/0002-pbf-derived-camera-source.md](docs/adr/0002-pbf-derived-camera-source.md).

By submitting a contribution, you agree that your code contribution is licensed under
**AGPL-3.0-only** and any data contribution under **ODbL-1.0**, and that you have the
right to license it under those terms.

## The non-negotiables

Changes must not weaken these project invariants:

- **Strict anonymity** — no third party ever receives a user's origin, destination, or
  route; no accounts, no PII, no persistent identifiers; logs must never retain route
  coordinates or client IPs. The only outbound handoff is the explicit, user-initiated
  "open in Apple/Google Maps" (with a warning).
- **Self-hosted geo stack** — routing (Valhalla), geocoding (Nominatim), and vector
  tiles are self-hosted. Don't introduce a third-party geo/tile/font/script dependency
  that the browser or backend calls at request time.
- **Camera avoidance** excludes the specific monitored road segment(s) via snap-to-road,
  not a radius.
- **Tests are required for every behavioral change** (Constitution Principle II). Geo
  services are stubbed with recorded fixtures so tests stay deterministic.

A change that touches any of these should call it out explicitly in the PR description.

## Getting set up

Everything runs in Docker — you do **not** need Ruby, Node, pnpm, or PostgreSQL on the
host. You need Docker Desktop (Compose v2), git, and curl. See the
[README](README.md#quick-start-local) for the one-command setup wizard.

For local development, **build a single US state** (the wizard defaults to one) — it's
fast and laptop-friendly. The whole-US production build is much heavier; see
[Whole-country / whole-US deployments](README.md#whole-country--whole-us-deployments).

## Running the checks locally

Run these (in Docker) before opening a PR — CI runs the same:

```bash
# Backend (RSpec, test env)
docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=test backend bundle exec rspec

# Frontend (Vitest + lint)
docker compose -f infra/docker-compose.yml run --rm frontend pnpm test -- run
docker compose -f infra/docker-compose.yml run --rm frontend pnpm lint

# Infra shell scripts (bats)
docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/build-geocoder.bats
```

## Pull requests

- Branch off `main`; keep PRs focused.
- Write a clear description: what changed, why, and any anonymity/security implications.
- Include tests for behavioral changes.
- Make sure CI is green.

## Reporting bugs and vulnerabilities

- **Security or privacy/anonymity issues:** do **not** open a public issue — follow
  [SECURITY.md](SECURITY.md).
- **Regular bugs and features:** open a GitHub issue with steps to reproduce and what you
  expected.
