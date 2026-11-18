#!/usr/bin/env bash
# Build a downloadable zip of hestia-migrate (run from repo root or scripts/)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER=$(cat "$ROOT/VERSION")
OUT="${1:-$ROOT/dist/hestia-migrate-${VER}.zip}"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(
	cd "$ROOT"
	zip -r "$OUT" . \
		-x '.git/*' \
		-x 'dist/*' \
		-x '*.zip' \
		-x '**/.DS_Store'
)
echo "Wrote $OUT"
