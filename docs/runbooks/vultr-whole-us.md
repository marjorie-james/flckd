# Sizing sheet — whole-US single-host deploy on Vultr

How to provision **one Vultr VPS** that hosts the entire-US deployment: all six
Kamal roles (web, job, postgres, routing, geocoder, tiles) co-located on the
private Docker network, same as [cheap-deploy.md](cheap-deploy.md) but sized for
the full-US geo substrate instead of a single small region.

Whole-US is a different sizing class from the Iowa launch. The binding
constraints come straight from [geo-stack.md](geo-stack.md):

- **Disk** — Nominatim's OSM import is the long pole; its Postgres volume reaches
  **250–350 GB** during osm2pgsql load + indexing. Add the whole-US TIGER bundle
  (~1.8 GB), the Valhalla graph (several GB), `tiles.pmtiles` (several GB), and the
  app's own Postgres → budget **~350–400 GB free, fast NVMe**.
- **RAM** — Nominatim/Planetiler OOM below ~16 GB during the import/tile build.
  The 16 GB floor is for the one-time **build spike**; steady-state is lighter.
- **Cores** — the Nominatim import scales with `NOMINATIM_THREADS`; more cores
  cut the multi-hour first-boot import.

Anonymity is unchanged: on one box the routing/geocoder/tiles accessories are
still private, reached by service name over the Docker network. Nothing here
touches FR-012a — no user origin/destination/route leaves the box.

> Prices below are Vultr list rates as of **June 2026**; confirm the exact
> bundled-disk figure per plan on Vultr's pricing page before you buy — Vultr
> bundles NVMe by RAM tier, and that bundle is what makes or breaks the disk
> budget. NVMe **Block Storage** is $0.10/GB/mo ($100/TB), HDD block is $25/TB.

---

## 1. Pick a plan

Two viable shapes. **Option A** is what I'd run; **Option B** is the cheapest
that still clears both constraints.

### Option A — 32 GB Cloud Compute (recommended)

One instance whose **bundled** NVMe already covers the import footprint, so there's
no second volume to manage.

| | Spec |
|---|---|
| Plan | Vultr Cloud Compute — **High Performance / Dedicated, ~8 vCPU / 32 GB RAM** |
| Disk | **~512 GB+ bundled NVMe** — clears the 350–400 GB budget with headroom |
| Cost | **~$190/mo** |
| Why | Single disk (no block-volume ops); extra cores speed the import; 32 GB gives the build spike room and leaves plenty for steady-state. |

### Option B — 16 GB Cloud Compute + NVMe Block Storage (budget)

Hits the 16 GB RAM floor, then bolts on a separate NVMe volume for the heavy geo
data so you're not paying for a 32 GB tier just to get disk.

| | Spec |
|---|---|
| Instance | Vultr Cloud Compute — **4 vCPU / 16 GB RAM**, ~320 GB bundled NVMe |
| Block volume | **~200 GB NVMe Block Storage** mounted for Docker's data-root |
| Cost | ~$96/mo instance + ~$20/mo block (200 GB × $0.10) = **~$116/mo** |
| Why | Decouples disk from RAM tier — cheapest way to satisfy both. **Must be the NVMe block tier, not HDD**: the import saturates IOPS and geo-stack.md flags fast NVMe as critical. |

### ❌ Don't: 16 GB instance, bundled disk only

16 GB RAM is fine, but the bundled ~320 GB is **just under** the documented
350–400 GB import footprint. RAM-adequate, disk-short — the Nominatim import can
fill the disk and take everything down. Either size up (A) or add block (B).

> One-time-spike trick (applies to either option): the 16 GB floor and the
> 350-GB peak are both **import-time**. You can provision big, run the import
> once, ship the prebuilt `nominatim-data` volume, then scale the instance down
> for steady-state — same play as cheap-deploy.md §1. Disk you can't easily
> shrink, so size disk for the peak regardless.

---

## 2. Provision the host

Identical to [cheap-deploy.md §3](cheap-deploy.md) (Ubuntu LTS, Docker, non-root
`deploy` user, key-only SSH, GHCR PAT, DNS A/AAAA → instance IP), plus two
Vultr-specific steps:

1. **Fix Vultr's IPv6-only resolver** so Docker containers can resolve DNS
   ([provisioning.md §](provisioning.md)). Easiest:
   ```bash
   infra/scripts/bootstrap-host.sh deploy@<INSTANCE_IP>   # idempotent
   ```
   or manually drop `{"dns":["1.1.1.1","8.8.8.8"]}` into `/etc/docker/daemon.json`.

2. **(Option B only) Attach + mount the block volume, then point Docker at it.**
   In the Vultr panel: create an **NVMe** Block Storage volume in the *same
   region* as the instance and attach it. It appears as e.g. `/dev/vdb`. Then:
   ```bash
   # Format once (destroys any data on the volume).
   sudo mkfs.ext4 /dev/vdb
   sudo mkdir -p /mnt/blockstore
   # Persist the mount (use the volume's UUID, not /dev/vdb, which can renumber).
   echo "UUID=$(sudo blkid -s UUID -o value /dev/vdb) /mnt/blockstore ext4 defaults,nofail 0 2" \
     | sudo tee -a /etc/fstab
   sudo mount -a

   # Relocate Docker's entire data-root onto the block volume. This captures
   # images AND every named/bind volume in one move — so all the geo accessory
   # data (nominatim-data, routing-data, tiles-data) and Postgres land on the
   # big NVMe with ZERO deploy.yml edits.
   sudo systemctl stop docker
   sudo rsync -aP /var/lib/docker/ /mnt/blockstore/docker/     # if Docker already ran
   sudo mkdir -p /etc/docker
   # Merge with the DNS fix from step 1 — keep both keys in one JSON object:
   #   { "dns": ["1.1.1.1","8.8.8.8"], "data-root": "/mnt/blockstore/docker" }
   sudoedit /etc/docker/daemon.json
   sudo systemctl start docker
   docker info | grep "Docker Root Dir"   # expect /mnt/blockstore/docker
   ```
   Relocating `data-root` is preferred over editing each accessory's
   `directories:` path — Kamal re-creates those volumes under the Docker root, so
   moving the root moves all of them and survives redeploys untouched.

---

## 3. Deploy

Same flow as [cheap-deploy.md §2–5](cheap-deploy.md): point every `<…_HOST>`
placeholder in `backend/config/deploy.yml` at the one instance IP, build the geo
artifacts on **free CI** (`build-geo.yml`) — never on the paid box — then
`kamal setup` → `db:prepare` → deploy the geo artifacts. The accessory definitions
in [`deploy.yml`](../../backend/config/deploy.yml) already bind to `127.0.0.1` and
already set `GEOCODER_COUNTRY: us`, so no per-role changes are needed for whole-US;
leave `GEOCODER_REGION_STATE` / `GEOCODER_VIEWBOX` empty so the app frames the
entire country.

### Whole-US tuning knobs (set before the import)

From [geo-stack.md §](geo-stack.md) — the defaults are tuned for a single state and
will be slow or OOM at US scale:

| Knob | Whole-US value | Why |
|---|---|---|
| `NOMINATIM_SHM` | **`4gb`** | Default `1gb` chokes the US osm2pgsql import. |
| `PLANETILER_XMX` | **`16g`** | JVM heap for the whole-US tile build. |
| `NOMINATIM_THREADS` | **`<nproc>`** | Import is the long pole; scales with cores. |
| `GEO_GEOCODER_TIMEOUT` | **raise (hours)** | US first-boot import takes hours, not the ~35 min state default. |
| `GEO_BUILD_JOBS` | all cores (cap if sharing) | Valhalla + Planetiler parallelism. |

---

## 4. Day-one essentials (unchanged, but matters more at scale)

All of [cheap-deploy.md §6](cheap-deploy.md) applies, with US-scale emphasis:

- **Disk alerting at ~75%** — non-negotiable. Nominatim + Postgres + tiles share
  one disk (or one block volume); the import peak is ~350 GB and a full disk takes
  everything down. Alert *before* the import, not after.
- **Backups** — `pg_dump` → off-box object storage; Postgres is the only
  irreplaceable state ([backups.md](backups.md)). The geo volumes are rebuildable
  from CI, so back up Postgres, not the 350 GB Nominatim index.
- **Rollback** — `kamal rollback` swaps the app image instantly; the geo volumes
  and Postgres do **not** roll back.

---

## 5. Cost summary

| Option | Monthly | What you get |
|---|---|---|
| **A — 32 GB single disk** | **~$190** | Simplest ops, headroom for build spike + steady-state, faster import. **Default pick.** |
| **B — 16 GB + 200 GB NVMe block** | **~$116** | Cheapest that clears both constraints; one extra volume to manage. |
| ❌ 16 GB bundled-only | ~$96 | Disk-short (~320 GB < 350–400 GB peak) — don't. |

Add a few $/mo for backup object storage. Registry (GHCR), CI geo builds, and
Let's Encrypt TLS are free. Vultr bills on a 672-hour monthly cap.

### Open questions worth a test-box measurement

geo-stack.md gives *during-import* and "several GB" figures, not finals. Before
committing to Option B's volume size, measure on a throwaway box:

- **Final indexed Postgres size** (the 250–350 GB is the import peak — steady-state
  is typically lower; if it lands well under, a smaller block volume works).
- **Exact Valhalla graph + `tiles.pmtiles` sizes** ("several GB" each).

If those finals come in low, size the block volume down — it's billed per-GB.
