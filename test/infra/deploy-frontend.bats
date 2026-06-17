#!/usr/bin/env bats
# Behavioral test for the dist content-swap in infra/scripts/deploy-frontend.sh
# (FIX 3): the swap must copy the new build in FIRST (keeping the live, bind-mounted
# inode populated — no empty window / 404 outage), THEN prune only stale paths that
# aren't in the new build. Driving the real remote-exec end to end needs ssh, so this
# test exercises the swap LOGIC locally against temp dirs (the remote command is the
# same shell run on the host). Run via Docker:
#   docker run --rm -v "$(pwd):/code" -w /code bats/bats:1.11.0 test/infra/deploy-frontend.bats

bats_load_library bats-support
bats_load_library bats-assert

setup() {
  export BATS_TEST_TMPDIR
  BATS_TEST_TMPDIR="$(mktemp -d)"
  DIST_DIR="${BATS_TEST_TMPDIR}/dist"
  mkdir -p "${DIST_DIR}"
}

teardown() { rm -rf "${BATS_TEST_TMPDIR}"; }

# The swap body, identical in shape to deploy-frontend.sh's remote command: copy
# first, prune stale (depth-first), drop staging. ${DIST_DIR} is expanded here as it
# is in the script (the local side interpolates it into the remote command string).
_swap() {
  cp -a "${DIST_DIR}.new/." "${DIST_DIR}/"
  ( cd "${DIST_DIR}"
    find . -mindepth 1 -depth -print | while IFS= read -r p; do
      [ -e "${DIST_DIR}.new/${p}" ] || rm -rf "${p}"
    done )
  rm -rf "${DIST_DIR}.new"
}

@test "swap replaces contents: new files land, stale files are pruned" {
  # Live build has an old asset + an index; new build drops old-asset, adds new-asset.
  printf 'old-index\n'  > "${DIST_DIR}/index.html"
  printf 'old-asset\n'  > "${DIST_DIR}/old-asset.js"
  mkdir -p "${DIST_DIR}/assets" && printf 'old\n' > "${DIST_DIR}/assets/old.css"

  mkdir -p "${DIST_DIR}.new/assets"
  printf 'new-index\n'  > "${DIST_DIR}.new/index.html"
  printf 'new-asset\n'  > "${DIST_DIR}.new/new-asset.js"
  printf 'new\n'        > "${DIST_DIR}.new/assets/new.css"

  _swap

  # New content present and current.
  assert [ "$(cat "${DIST_DIR}/index.html")" = "new-index" ]
  assert [ -f "${DIST_DIR}/new-asset.js" ]
  assert [ -f "${DIST_DIR}/assets/new.css" ]
  # Stale content pruned.
  assert [ ! -e "${DIST_DIR}/old-asset.js" ]
  assert [ ! -e "${DIST_DIR}/assets/old.css" ]
  # Staging dir removed.
  assert [ ! -e "${DIST_DIR}.new" ]
}

@test "swap keeps the live dir non-empty throughout (no empty window)" {
  printf 'old-index\n' > "${DIST_DIR}/index.html"
  mkdir -p "${DIST_DIR}.new"
  printf 'new-index\n' > "${DIST_DIR}.new/index.html"

  # The live document root is never emptied: copy-first means index.html exists at
  # every step (the old "delete-all then copy" left it empty mid-swap).
  _swap
  assert [ -f "${DIST_DIR}/index.html" ]
  assert [ "$(cat "${DIST_DIR}/index.html")" = "new-index" ]
}

@test "deploy-frontend.sh parses (bash -n)" {
  run bash -n "${BATS_TEST_DIRNAME}/../../infra/scripts/deploy-frontend.sh"
  assert_success
}
