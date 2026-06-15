# Contract: Country registry (internal)

`Geocoding::CountryRegistry` — static reference data resolving the configured country
to everything provisioning + geocoding need. Internal contract (no HTTP surface).

## Resolution

- Input: `GEOCODER_COUNTRY` env (backend) / `COUNTRY` in `infra/.region` (scripts).
- Unspecified → resolves to `us` (FR-002).
- Lookup returns a country record (below) or **raises a clear, actionable error** for
  an unknown / un-provisioned code (FR-009) — no silent substitution.

## Country record

```
{
  code:            "us",
  name:            "United States",
  extract_url:     "https://download.geofabrik.de/north-america/us-latest.osm.pbf",
  bbox:            [-125.0, 24.5, -66.9, 49.5],   # [west, south, east, north]
  tiger:           true,                           # US Census TIGER house numbers apply
  sub_region_kind: "state"
}
```

## Consumers

| Consumer | Uses |
|----------|------|
| `GeocoderClient` | `bbox` → viewbox/bounded search; gates single-state workaround off when country-spanning |
| `coverage_controller` (`/bounds`) | `bbox` → map-framing extent |
| `db/seeds.rb` | seed the configured country's dev data-region (framing extent is registry-derived) |
| `fetch-extract.sh` | `extract_url` → country OSM download |
| `build-geocoder.sh` | `tiger` → import all counties (US) or skip (non-US) |

## Launch invariant

Only `us` is populated and validated at launch. Adding a country = adding a populated
record **and** provisioning its data; until both exist, that code fails setup (FR-009).
