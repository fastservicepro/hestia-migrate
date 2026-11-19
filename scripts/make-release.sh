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

# Copy tree without VCS, build output, or IDE/agent tooling
RSYNC_EXCLUDES=(
	--exclude '.git'
	--exclude 'dist'
	--exclude '.cursor'
	--exclude '.idea'
	--exclude '.vscode'
	--exclude '.agent'
	--exclude 'agent-transcripts'
	--exclude '*.plan.md'
)
if command -v rsync >/dev/null 2>&1; then
	rsync -a "${RSYNC_EXCLUDES[@]}" "$ROOT/" "$STAGE/hestia-migrate/"
else
	mkdir -p "$STAGE/hestia-migrate"
	cp -a "$ROOT"/. "$STAGE/hestia-migrate/"
	rm -rf "$STAGE/hestia-migrate/.git" \
		"$STAGE/hestia-migrate/dist" \
		"$STAGE/hestia-migrate/.cursor" \
		"$STAGE/hestia-migrate/.idea" \
		"$STAGE/hestia-migrate/.vscode" \
		"$STAGE/hestia-migrate/.agent" \
		"$STAGE/hestia-migrate/agent-transcripts"
	find "$STAGE/hestia-migrate" -name '*.plan.md' -delete 2>/dev/null || true
fi

(
	cd "$STAGE"
	zip -r "$DIST/hestia-migrate-${VER}.zip" hestia-migrate \
		-x '*/.git/*' -x '*/dist/*' \
		-x '*/.cursor/*' -x '*/.idea/*' -x '*/.vscode/*' \
		-x '*/.agent/*' -x '*/agent-transcripts/*' \
		-x '**/*.plan.md' -x '**/.DS_Store'
)
cp -f "$DIST/hestia-migrate-${VER}.zip" "$DIST/hestia-migrate.zip"

echo "Wrote:"
echo "  $DIST/hestia-migrate-${VER}.zip"
echo "  $DIST/hestia-migrate.zip"
echo "Attach BOTH to GitHub Release v${VER} (stable name keeps /releases/latest/download/hestia-migrate.zip working)."
