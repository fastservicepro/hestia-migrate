#!/usr/bin/env bash
# Build release zips: versioned + stable name for GitHub /releases/latest/download/
# Run from repo root: bash scripts/make-release.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER=$(tr -d ' \t\r\n' <"$ROOT/VERSION")
DIST="$ROOT/dist"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$DIST"
rm -f "$DIST/hestia-migrate-${VER}.zip" "$DIST/hestia-migrate.zip"

# Copy tree without .git / dist
if command -v rsync >/dev/null 2>&1; then
	rsync -a --exclude '.git' --exclude 'dist' "$ROOT/" "$STAGE/hestia-migrate/"
else
	mkdir -p "$STAGE/hestia-migrate"
	cp -a "$ROOT"/. "$STAGE/hestia-migrate/"
	rm -rf "$STAGE/hestia-migrate/.git" "$STAGE/hestia-migrate/dist"
fi

(
	cd "$STAGE"
	zip -r "$DIST/hestia-migrate-${VER}.zip" hestia-migrate \
		-x '*/.git/*' -x '*/dist/*' -x '**/.DS_Store'
)
cp -f "$DIST/hestia-migrate-${VER}.zip" "$DIST/hestia-migrate.zip"

echo "Wrote:"
echo "  $DIST/hestia-migrate-${VER}.zip"
echo "  $DIST/hestia-migrate.zip"
echo "Attach BOTH to GitHub Release v${VER} (stable name keeps /releases/latest/download/hestia-migrate.zip working)."
