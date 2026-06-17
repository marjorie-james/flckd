#!/usr/bin/env bats
# Behavioral tests for infra/scripts/provision-geo-host.sh — the accessory-resolution
# guard (FIX 5: absent container = graceful skip; present-but-unresolved mount = loud
# exit 1) and the extract cache region marker (FIX 6: a scope change re-downloads).
#
# The script's host/SSH work is driven entirely through sshx()/scp, so a stubbed
# `ssh`/`scp`/`curl` makes it fully offline. The stub `ssh` interprets the remote
# command string (its last arg) and is configured via PROV_* env vars. Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/provision-geo-host.bats

bats_load_library bats-support
bats_load_library bats-assert

SCRIPT="${BATS_TEST_DIRNAME}/../../infra/scripts/provision-geo-host.sh"

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"

  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  # Configurable `ssh` stub. PROV_ACCESSORIES_PRESENT=1 makes `docker inspect <c>`
  # succeed (container present); the --format inspect returns PROV_MOUNT (empty by
  # default → unresolved mount). PROV_EXTRACT_CACHED=1 makes the extract + marker
  # cache check pass (skips download). Everything else is a benign success.
  cat > "${BATS_TEST_TMPDIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"  # last arg = remote command string
case "${cmd}" in
  *"docker inspect"*"--format"*)
    # accessory_dir: echo the (possibly empty) resolved mount source.
    [ "${PROV_ACCESSORIES_PRESENT:-0}" = "1" ] && printf '%s' "${PROV_MOUNT:-}"
    exit 0 ;;
  *"docker inspect"*)
    # accessory_exists: succeed iff the container is "present".
    [ "${PROV_ACCESSORIES_PRESENT:-0}" = "1" ] && exit 0 || exit 1 ;;
  *'echo "$HOME"'*|*'$HOME'*)
    echo "/home/deploy"; exit 0 ;;
  *"extract.osm.pbf.url"*)
    # Cache marker compare (test -f marker && [ cat == URL ]) and the post-download
    # marker write both contain the marker path. A `printf ... >` write is a plain
    # success; the compare succeeds only when the cache is configured present.
    case "${cmd}" in
      *"printf"*) exit 0 ;;
      *) [ "${PROV_EXTRACT_CACHED:-0}" = "1" ] && exit 0 || exit 1 ;;
    esac ;;
  *"test -s"*"extract.osm.pbf"*)
    [ "${PROV_EXTRACT_CACHED:-0}" = "1" ] && exit 0 || exit 1 ;;
  *"status.php"*)
    exit 1 ;;  # geocoder not ready (forces the place+reboot branch if reached)
  *)
    exit 0 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/ssh"

  # scp + curl stubs: record nothing, just succeed.
  cat > "${BATS_TEST_TMPDIR}/bin/scp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
# fetch-extract style: write a dummy file for any -o <dest>.
prev=""; dest=""
for a in "$@"; do [ "${prev}" = "-o" ] && dest="${a}"; prev="${a}"; done
[ -n "${dest}" ] && printf 'dummy\n' > "${dest}"
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/scp" "${BATS_TEST_TMPDIR}/bin/curl"

  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  # Minimal deploy.yml (routing host) for resolve_target_host.
  export DEPLOY_YML="${BATS_TEST_TMPDIR}/deploy.yml"
  cat > "${DEPLOY_YML}" <<'EOF'
ssh:
  user: deploy
accessories:
  routing:
    host: 10.0.0.9
EOF

  # Isolate region config; default-US resolves the whole-US extract.
  export REGION_CONFIG="${BATS_TEST_TMPDIR}/.region"
  export GEO_ENV="${BATS_TEST_TMPDIR}/geo.env"  # absent → no deploy-scope override
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# ---------------------------------------------------------------------------
# FIX 5 — accessory resolution
# ---------------------------------------------------------------------------

@test "absent accessories are a graceful skip (exit 0, geo never built loudly)" {
  # No containers present; extract is cached so no download is attempted.
  PROV_ACCESSORIES_PRESENT=0 PROV_EXTRACT_CACHED=1 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "<accessory not found>"
}

@test "a present accessory with an unresolved mount fails loudly (exit 1)" {
  # Containers present but the data mount can't be resolved (empty PROV_MOUNT).
  PROV_ACCESSORIES_PRESENT=1 PROV_MOUNT="" PROV_EXTRACT_CACHED=1 run bash "${SCRIPT}"
  assert_failure
  assert_output --partial "could not be resolved"
}

# ---------------------------------------------------------------------------
# FIX 6 — extract cache region marker (a scope change re-downloads)
# ---------------------------------------------------------------------------

@test "a cache MISS (no matching marker) takes the download path" {
  # Not cached → the script downloads locally and streams to the host.
  PROV_ACCESSORIES_PRESENT=0 PROV_EXTRACT_CACHED=0 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "downloading locally"
}

@test "a cache HIT for the same region skips the download" {
  PROV_ACCESSORIES_PRESENT=0 PROV_EXTRACT_CACHED=1 run bash "${SCRIPT}"
  assert_success
  assert_output --partial "extract already on host for this region"
  refute_output --partial "downloading locally"
}
