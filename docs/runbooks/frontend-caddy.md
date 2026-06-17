# Runbook: Frontend + Caddy single-origin edge

The frontend and backend run on **one VPS, one origin**, fronted by **Caddy**.
Caddy serves the static React build and reverse-proxies same-origin `/api` and
`/tiles` to the backend services, so the whole app is a single origin: no CORS,
nothing cross-site, and a user's route never leaves our box (FR-012a).

## Topology

```
                  ┌──────────────── VPS <VPS_IP> ────────────────┐
   flckd.com ──►  │  flckd-caddy  :80/:443   (auto-TLS, public edge)  │
   www  ─► apex   │   ├─ /api/*   → kamal-proxy:80  (Host api.flckd.com)│ ← zero-downtime
                  │   ├─ /tiles/* → flckd-backend-tiles:8080            │
                  │   └─ /*       → /srv/dist  (static SPA, /fonts,     │
                  │                 /config.json, map-style.json)       │
                  └───────────────────────────────────────────────────┘
        Caddy, kamal-proxy, the app, and the tileserver share the `kamal`
        Docker network, so Caddy reaches the backend by container name and
        nothing but Caddy needs a host port.
```

- **Single origin** → `frontend/public/config.json` stays `apiBase:""`,
  `tilesBase:""` (same-origin). The map style requests `/tiles/{z}/{x}/{y}.mvt`
  and `/fonts/...` same-origin; go-pmtiles serves our `tiles.pmtiles` archive at
  exactly `/tiles/{z}/{x}/{y}.mvt`, and fonts are vendored into the build.
- **Caddy terminates TLS**; kamal-proxy sits behind it speaking plain HTTP and
  only does zero-downtime app version switching.

## DNS

| Type | Name | Value |
|------|------|-------|
| `A` | `flckd.com` (`@`) | `<VPS_IP>` |
| `A` | `www` | `<VPS_IP>` |

- Caddy auto-provisions Let's Encrypt/ZeroSSL certs for both once the records
  resolve; `www` redirects to the apex.
- On **Cloudflare**, set both records **DNS-only (grey cloud)** until certs issue
  (HTTP-01 must reach Caddy), then optionally re-enable proxy with Full-Strict.
- `api.flckd.com` is **not needed** in the single-origin model (the frontend uses
  same-origin `/api`). The Host `api.flckd.com` only lives *inside* the box as the
  label kamal-proxy routes on; Caddy sets it on the upstream request.

## Deploy / update the frontend

```bash
# Build (if needed), stream dist/ + Caddyfile to the host, boot/reload Caddy:
infra/scripts/deploy-frontend.sh                 # uses frontend/dist if present
FORCE_BUILD=1 infra/scripts/deploy-frontend.sh   # rebuild the bundle first
```

`dist/` is served from a host bind mount, so a frontend-only change is just a
re-sync + `caddy reload` — no container rebuild. Config comes from
`backend/.kamal/frontend.env` (gitignored; copy `frontend.env.example`):
`FLCKD_DOMAIN`, `ACME_EMAIL`, and `API_HOST` (defaults to deploy.yml `proxy.host`).

To re-point the running app at a different API/tiles origin without rebuilding,
edit `dist/config.json` on the host (it is served `Cache-Control: no-store`).

## How Caddy and Kamal-proxy coexist (the one non-obvious bit)

Both want host `:80/:443`. Kamal-proxy yields them:

1. `backend/config/deploy.yml` → `proxy.ssl: false` (Caddy does TLS; kamal-proxy
   speaks HTTP). It still routes by `host: api.flckd.com`.
2. `backend/config/deploy.yml` → `proxy.run.publish: false`, so kamal-proxy binds
   **no host ports** — Caddy reaches it at `kamal-proxy:80` over the `kamal`
   network. Kamal re-applies this on **every** proxy boot, so it survives
   `kamal proxy remove --force` and full teardowns.
3. `kamal proxy reboot` then `kamal deploy` re-register the app on the port-free
   HTTP proxy.

> **Why `proxy.run.publish` and not the old host file.** Kamal used to take this
> from a host-side `~/.kamal/proxy/options` file (no `--publish`). That was
> fragile: `kamal proxy remove --force` *deletes* it, after which the next boot
> falls back to the default `--publish 80:80 --publish 443:443` and collides with
> Caddy (`Bind for :::80 failed: port is already allocated`). The deploy-config
> path is durable and authoritative — it even overrides a stale host file. The
> `boot_config` CLI (`kamal proxy boot_config set --no-publish`) still works but is
> deprecated in favour of `proxy/run`.

> If you ever `kamal proxy reboot`, the routing table is rebuilt on the next
> `kamal deploy` — run one if `/api` 502s after a proxy change.

## Troubleshooting

- **`target failed to become healthy` on setup/deploy, but the app is fine.**
  Almost always DNS: kamal-proxy can't resolve/reach the app container. Check
  `kamal proxy logs` for `Healthcheck failed ... network is unreachable`. Two
  causes, both seen here:
  - The host hands containers an unreachable (IPv6-only) resolver — fix with
    `infra/scripts/bootstrap-host.sh` (see `provisioning.md` §2). The
    `infra/scripts/preflight-host.sh` check catches this before the deploy.
  - kamal-proxy is **not on the `kamal` network** (it landed on the default
    bridge, so it has no Docker embedded DNS). Confirm from a container on the
    network: `docker run --rm --network kamal busybox nslookup kamal-proxy` should
    return an address. If it doesn't, `kamal proxy reboot -y` re-attaches it.
- **`kamal proxy reboot` hangs / spews.** It prompts "Are you sure?" — always pass
  `-y` from non-interactive shells, or it loops forever on the unanswered prompt.

## Caveats

- **TLS waits on DNS.** Caddy retries ACME until `flckd.com` resolves to the box;
  until then it serves an internal cert and the public site isn't reachable.
- **Caddy is not (yet) a Kamal accessory.** It's a standalone container managed by
  `deploy-frontend.sh`, deliberately decoupled from the app deploy. `caddy:2` is
  unpinned — pin a digest (`CADDY_IMAGE=`) for reproducibility if you care.
- **Use the Caddy template.** `proxy.ssl: false` + `proxy.run.publish: false` are
  specific to this Caddy-fronted box, so they live in their own tracked template,
  `backend/config/deploy.caddy.example.yml` — start from it
  (`cp config/deploy.caddy.example.yml config/deploy.yml`). The plain
  `deploy.example.yml` keeps `ssl: true` and publishes ports for a standalone
  (no-Caddy) deploy where kamal-proxy is itself the public edge.
- **Backend host allow-list:** the app must accept `Host: api.flckd.com` (it does;
  that's the kamal-proxy route). If you change `API_HOST`, keep them in sync.
```
