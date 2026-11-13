#!/usr/bin/env bash
# Builds the app for the browser and serves the mini emulator.
#   tool/emulator/run.sh [port]        (default port 8090)
# Then open http://localhost:<port>/emulator.html
set -euo pipefail
cd "$(dirname "$0")/../.."
PORT="${1:-8090}"

# SQLite for the browser (one-off; the two files are committed in web/).
if [ ! -f web/sqlite3.wasm ] || [ ! -f web/sqflite_sw.js ]; then
  dart run sqflite_common_ffi_web:setup
fi

# --no-web-resources-cdn bundles the renderer so it works without internet.
flutter build web -t tool/emulator/main.dart --no-web-resources-cdn --no-wasm-dry-run
cp tool/emulator/emulator.html build/web/emulator.html

echo "Emulator: http://localhost:${PORT}/emulator.html"
exec python3 -m http.server "$PORT" --directory build/web
