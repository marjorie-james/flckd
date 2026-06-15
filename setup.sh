#!/usr/bin/env bash
#
# flckd — first-time setup.
#
# This is a thin convenience wrapper so you can get started from the repo root
# with a single command:
#
#   ./setup.sh
#
# It simply runs the real setup wizard at infra/scripts/setup.sh and forwards
# any flags (e.g. -v for verbose, --region CA to skip the prompt).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/infra/scripts/setup.sh" "$@"
