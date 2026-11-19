#!/bin/bash
# Serves Shared/Resources on http://localhost:8642, so an app started with `-ContentSource http://localhost:8642` reads
# the data files as they are on disk, edits included, at every launch: no rebuild, no content.json needed. Works for
# the Mac app (which is sandboxed, so it can't read the folder itself) and the simulator.
#
#   scripts/serve-content.sh [port]
set -euo pipefail
cd "$(dirname "$0")/.."
port="${1:-8642}"
echo "Serving Shared/Resources on http://localhost:$port (Ctrl-C to stop). Launch the app with:"
echo "  -ContentSource http://localhost:$port"
exec python3 -I -m http.server "$port" --bind 127.0.0.1 --directory Shared/Resources
