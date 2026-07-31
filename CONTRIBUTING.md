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
  coordinates or client IPs. There is no network transmission exception: a route leaves the
  app only as a user-initiated, fully client-side GPX export (built in the browser, saved to
  the user's own device — nothing is sent anywhere; the user is warned the file itself holds
  their route).
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

Run these (in Docker) before opening a PR — CI runs the same.

Prepare the test database first. The compose Postgres seeds only
`flckd_development`, so the `RAILS_ENV=test` suite has no database to connect to until
you create one:

```bash
docker compose -f infra/docker-compose.yml up -d postgres
docker compose -f infra/docker-compose.yml run --rm --no-deps -e RAILS_ENV=test backend bin/rails db:prepare
```

Re-run that `db:prepare` after pulling changes that add migrations, otherwise the suite
runs against a stale schema.

```bash
# Backend (RuboCop, Brakeman, RSpec)
docker compose -f infra/docker-compose.yml run --rm --no-deps backend bundle exec rubocop
docker compose -f infra/docker-compose.yml run --rm --no-deps backend bundle exec brakeman -q --no-pager --exit-on-warn --exit-on-error
docker compose -f infra/docker-compose.yml run --rm --no-deps -e RAILS_ENV=test -e COVERAGE=1 backend bundle exec rspec

# Frontend (ESLint, dependency audit, typecheck, Vitest)
docker compose -f infra/docker-compose.yml run --rm --no-deps frontend pnpm lint
docker compose -f infra/docker-compose.yml run --rm --no-deps frontend pnpm audit --prod --audit-level high
docker compose -f infra/docker-compose.yml run --rm --no-deps frontend pnpm exec tsc -b --noEmit
docker compose -f infra/docker-compose.yml run --rm --no-deps frontend pnpm exec vitest run

# Infra shell scripts (bats)
docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra
```

Keep `--no-deps` on those `compose run` commands. The `backend` service declares
`depends_on` for the geo stack (and `frontend` depends on `backend`), so without it
Compose starts the geocoder, whose first run kicks off a Nominatim OSM import that takes
roughly 20 minutes before it is healthy. The tests stub the geo services, so none of them
are needed. Postgres is the one real dependency, which is why it is started explicitly
above.

### After a lockfile change

`backend` mounts a `bundle_cache` volume over `/usr/local/bundle` and `frontend` mounts
`frontend_node_modules` over `/app/node_modules`. Those named volumes shadow what the
image built, so a changed `Gemfile.lock` or `pnpm-lock.yaml` shows up as confusing
missing-dependency errors until you reinstall inside the service:

```bash
docker compose -f infra/docker-compose.yml run --rm --no-deps backend bundle install
docker compose -f infra/docker-compose.yml run --rm --no-deps frontend pnpm install
```

RuboCop and Brakeman are part of the required `backend` gate, and the dependency audit and
typecheck are part of the required `frontend` gate — a PR that only passes the test runners can
still fail CI. `shellcheck` is its own required gate; CI runs
`shellcheck --severity=warning --exclude=SC1091,SC2034 infra/scripts/*.sh`. The bats command above
runs everything under `test/infra`, a superset of the file list in
[`.github/workflows/ci-scripts.yml`](.github/workflows/ci-scripts.yml), which is the authority on
what CI actually runs. `bundler-audit` runs in CI too but is deliberately non-blocking.

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
