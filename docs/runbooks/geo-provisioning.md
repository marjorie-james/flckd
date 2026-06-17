# Runbook: Provisioning the geo substrate onto a Kamal host

This explains how the self-hosted geo substrate (routing graph, vector tiles,
geocoder import) gets onto a **single co-located Kamal box**, why it is built the
way it is, and the production bring-up fixes that had to land first. If you run a
multi-host or CI deploy, prefer the release-based pipeline (`build-geo.yml` →
`deploy-geo.yml`, see [geo-stack.md](geo-stack.md)); this runbook is the
in-place, single-box automation.

Anonymity reminder: every host here is **our own**. Routing, geocoding, and tiles
run as private Kamal accessories built from **public OSM data** — no user
origin/destination/route ever leaves the box (FR-012a).

## TL;DR

`backend/bin/kamal-docker setup` (or `deploy`) runs
`infra/scripts/provision-geo-host.sh` automatically after the app comes up. The
script:

1. downloads the OSM extract **on your machine** and streams it to the host,
2. builds the routing graph (Valhalla) and vector tiles (Planetiler) **on the
   host**, straight into the accessory data dirs,
3. places the extract for the geocoder and reboots it (Nominatim imports on boot).

It is **idempotent** — a no-op once each stage has actually completed (it tracks
build-completion markers + geocoder readiness, not just whether a file exists) —
so it is safe to leave wired into every deploy. Skip it with `GEO_PROVISION=skip`.
Run it standalone:

```bash
infra/scripts/provision-geo-host.sh [user@host]
```

## Why it is "roundabout" — the constraints that force this shape

Three host realities drive the design. None is incidental; each is the reason a
"just build it normally" approach fails.

### 1. Build ON the host, not locally — because the build images are amd64

Valhalla and Planetiler ship **amd64-only** images. On an Apple-silicon (arm64)
dev machine they run under QEMU emulation: a graph/tile build that takes minutes
natively can take *many times longer* emulated, and you'd then have to copy
hundreds of MB of output up to the host. The production box is amd64, already has
Docker, and already has the accessory data dirs mounted — so we build there,
natively, in place. No emulation, no large upload of build *output*.

### 2. Download the extract LOCALLY, then stream it — because Geofabrik throttles the host

The host has normal outbound internet (it pulls registry images, reaches GitHub
in ~0.2 s), but `download.geofabrik.de` **times out from the host entirely** — a
`HEAD` connects, a bodied `GET` hangs at 0 bytes. Geofabrik commonly rate-limits
or blackholes datacenter/cloud IPs (this box is one). The same download from a
normal connection (your laptop / a CI runner) works fine.

So the script downloads the extract on **the machine running kamal** and streams
it to the host over the existing SSH connection (`scp`). The host never has to
reach Geofabrik. This is the single biggest "why is this indirect" — it exists
because the host cannot fetch its own source data.

> Geofabrik's download proxy also intermittently returns `502/503` even from a
> good connection (a brief hiccup mid-update window). The local download retries
> generously (`--retry 6 --retry-all-errors`) so a transient blip doesn't abort
> the whole provisioning.

### 3. Write through the accessory data dirs as root — because the accessories own them

Each accessory writes to its mounted dir as **container-root**, so those dirs end
up root-owned on the host and the `deploy` user can't `cp` into them. The build
containers (which run as root) therefore mount the *deploy-owned* build dir
read-only at `/src` for the extract and write their output into the *root-owned*
accessory dir at `/data`. We never `cp` from the host into an accessory dir.

> Gotcha that bit us: `docker run -v <src>:/data` treats a **relative or bare**
> `src` as a *named volume* (empty), not a host bind mount. The build dir must be
> an **absolute** host path, so the script resolves `$HOME` on the host first.

## Routing fails soft now (no more crash-loop)

`valhalla_service` exits non-zero on an empty/missing `valhalla.json` ("Could not
parse json, error at offset: 0"), so a freshly-set-up routing accessory whose
graph isn't built yet used to **crash-loop**. The accessory `cmd` now generates a
default `valhalla.json` when the volume is empty, so the service stays up
(logging `Tile extract could not be loaded`) until the graph is provisioned —
then the guard is a no-op because the real `valhalla.json` is already present.
This is what the provisioning runbook means by "routing fails soft until the
substrate is built."

(The `traffic.tar No such file or directory` warning in the routing log is
**expected and harmless** — we don't ship live-traffic tiles.)

## Deploy scope is independent of your local dev scope

`infra/.region` is your **local docker-compose** scope. The **deploy** scope is
separate, so you can develop against one state and deploy a different state or the
whole US. Set it in `backend/.kamal/geo.env` (gitignored; copy `geo.env.example`)
or per invocation. Resolution precedence:

1. `GEO_REGION_URL` (one Geofabrik extract) or `GEO_COUNTRY` (whole country) in the env
2. `backend/.kamal/geo.env`
3. `infra/.region` (fallback only)
4. the country registry default (whole US)

```bash
GEO_REGION_URL=https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf bin/kamal-docker deploy
GEO_COUNTRY=us bin/kamal-docker setup        # whole-US substrate
```

> A non-US country deploy should also match the app's `GEOCODER_COUNTRY` in
> `config/deploy.yml`. Every US **state** is `GEOCODER_COUNTRY=us`, so a
> single-state or whole-US deploy needs no change there.

This scope configures the deployed **app**, not just the data it's built from.
`bin/kamal-docker` resolves it (via `infra/scripts/deploy-scope-env.sh`) and writes
`backend/.kamal/deploy-scope.env` (gitignored); `.kamal/secrets` reads that file and
Kamal injects `GEOCODER_REGION_STATE` + `GEOCODER_VIEWBOX` (declared under `env.secret`
in `deploy.yml` — already present in `deploy.example.yml`). So a **single-state deploy
makes the app frame the map on — and geocode within — that state** (it never opens zoomed
out to the whole US), while a whole-country deploy leaves both empty and frames the entire
country. The state's bbox comes from the shared
[`infra/scripts/state-registry.sh`](../../infra/scripts/state-registry.sh), matched from
the `GEO_REGION_URL` slug — the same table the dev wizard uses, so dev and prod frame a
given state identically.

> The scope files (`geo.env`, `.region`) are **parsed, not sourced**, so an unquoted
> multi-word `GEO_REGION_LABEL` won't break a deploy — but quote it anyway
> (`GEO_REGION_LABEL="New York"`) so `provision-geo-host.sh`, which still sources the file
> for its own build step, is happy too.

## Why the wrapper, not a Kamal hook

A Kamal `post-deploy` hook runs **inside the Kamal image**, which has `ssh`/`awk`
but **no `bash` or `curl`** — and the provisioning is a bash script that needs to
download and drive Docker over SSH. So provisioning runs from `bin/kamal-docker`
**on your machine** (full tooling, your SSH agent) right after Kamal exits 0, not
as an in-container hook. A failed provisioning **does not fail the deploy** (the
app is already up); it warns and tells you to re-run.

## Caveats

- **Geocoder import is asynchronous.** Placing the extract + reboot kicks off the
  Nominatim import; the container stays up but `status.php` reports not-ready
  until it finishes (~10–20 min for a state, hours for whole-US). Watch:
  `docker logs -f flckd-backend-geocoder`.
- **House-number geocoding (TIGER) is a follow-on.** `provision-geo-host.sh` gets
  base geocoding working (OSM house numbers). US TIGER house numbers + Wikipedia
  importance are added by `infra/scripts/build-geocoder.sh`, which needs the OSM
  import *complete* first. It self-heals on a later run.
- **The build loads the production box.** Routing + tile builds use host CPU/RAM.
  For a state this is minutes and fine; for whole-US, provision during a quiet
  window or use the release-based pipeline instead.
- **Single-box assumption.** The script targets one host (the routing accessory's
  host from `deploy.yml`) and assumes the other accessories are co-located. For
  split geo hosts, use `deploy-geo.yml`.
- **Idempotency is completion-aware, not just file-presence.** Routing and tiles
  skip on a completion marker (`.graph-complete` / `.tiles-complete` in the data
  dir) written only after the build *and* the accessory restart succeed — so a
  half-written/truncated artifact from an interrupted build is never mistaken for
  a finished one, and a failed restart self-heals on the next run. The geocoder
  skips on `status.php` **readiness**, so a completed import is detected while a
  failed one isn't masked by the extract still on disk. An import that's merely
  *in progress* is left running (never restarted mid-import). Use `FORCE=1` to
  rebuild after a region change, or to force a stuck geocoder import to retry.

## Production bring-up fixes (what had to land first)

Getting the app itself to boot under Kamal required three fixes, all on `main`:

| Problem | Symptom | Fix |
|---------|---------|-----|
| `deploy@host` in every `deploy.yml` host value **and** `ssh.user: deploy` | Kamal silently booted **no** app containers (`container_prefix for nil`); roles didn't bind to the host | Use **bare** host addresses; `ssh.user` supplies the user. (Set the CI `WEB_HOST`/`JOB_HOST`/… variables to bare IPs too.) |
| `secret_key_base` was the un-interpolated placeholder `#{new_secret}` in `credentials.yml.enc` (a YAML comment → nil) | `Missing secret_key_base for 'production'` on boot | Generate a stable `SECRET_KEY_BASE` (Rails reads it from the env with precedence over credentials); `bin/kamal-docker` mints it once into `.kamal/secrets.env` and forwards it |
| Dockerfile set `USER` before copy and never ensured runtime dirs | `Errno::EACCES` creating `/rails/tmp`; container never healthy | Create + `chown` `tmp`/`log`/`storage` to `rails` as root before dropping privileges |

## Teardown (full wipe, for a clean re-setup)

`kamal remove` can't delete the accessory data dirs (they're container-root
owned), so a full wipe needs a root helper container on the host:

```bash
ssh deploy@<host> '
  # All flckd containers (backend accessories AND the flckd-caddy edge) + the proxy.
  # Caddy must go before the network rm, or "network has active endpoints" fails.
  docker ps -aq --filter name=flckd- | xargs -r docker rm -f
  docker rm -f kamal-proxy 2>/dev/null
  docker network rm kamal 2>/dev/null
  # Anchored so we only remove OUR volumes, not any volume containing "kamal".
  docker volume ls -q | grep -E "^(flckd-|kamal-proxy-)" | xargs -r docker volume rm
  # $HOME (not a hardcoded /home/deploy) and flckd-* covers backend + frontend + caddy dirs.
  docker run --rm -v "$HOME:/work" alpine sh -c "rm -rf /work/flckd-* /work/.kamal /work/geo-build"
'
```
