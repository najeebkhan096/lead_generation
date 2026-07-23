#!/usr/bin/env bash
# Build Flutter web (same-origin API) and copy into backend/public for Express.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "${FLUTTER_BIN}" && -x /Users/najeebkhan/Downloads/flutter/bin/flutter ]]; then
  FLUTTER_BIN=/Users/najeebkhan/Downloads/flutter/bin/flutter
fi
if [[ -z "${FLUTTER_BIN}" ]]; then
  echo "flutter not found" >&2
  exit 1
fi

cd "$ROOT/frontend"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build web --release --dart-define=API_BASE_URL=

rm -rf "$ROOT/backend/public"
mkdir -p "$ROOT/backend/public"
cp -R "$ROOT/frontend/build/web/." "$ROOT/backend/public/"
echo "Copied Flutter web → backend/public"
