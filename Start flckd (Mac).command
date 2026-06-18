#!/bin/bash
#
# flckd — double-click launcher for macOS.
#
# A non-technical user can double-click this file in Finder: macOS opens it in
# Terminal and runs the setup wizard. No command line knowledge required.
#
# First launch from a downloaded ZIP: macOS may say the file is "from an
# unidentified developer". Right-click the file → Open → Open to allow it once
# (this is Gatekeeper, not an error). A `git clone` keeps the executable bit, so
# double-click works directly there.
#
# All this wrapper does is move to the repo, make sure the scripts are runnable
# (a ZIP download can strip the executable bit), and hand off to ./setup.sh.
set -euo pipefail

# The repo root is this file's own directory.
cd "$(dirname "$0")"

# Self-heal executable bits the ZIP path can drop, so ./setup.sh and the build
# scripts it calls will run. Harmless when they're already executable.
chmod +x ./setup.sh 2>/dev/null || true
chmod +x ./infra/scripts/*.sh 2>/dev/null || true

echo
echo "  Starting flckd setup… (this window will show progress)"
echo

# Run the wizard. Pass through any args (none on a plain double-click → the
# interactive state prompt). Capture status so we can pause before closing.
status=0
./setup.sh "$@" || status=$?

# Keep the Terminal window open so the user can read the result / any error,
# but only when attached to a real terminal (so automated runs don't block).
if [ -t 0 ]; then
  echo
  read -r -p "  Press Return to close this window… " _ || true
fi
exit "$status"
