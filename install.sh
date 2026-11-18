#!/usr/bin/env bash
# Install hestia-migrate as a standalone downloadable module for HestiaCP.
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
	echo "Run as root: sudo bash install.sh" >&2
	exit 1
fi

if [[ ! -d /usr/local/hestia ]]; then
	echo "Hestia Control Panel not found in /usr/local/hestia" >&2
	exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/local/hestia-migrate
VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo "1.0.0")

echo "==> Installing hestia-migrate $VERSION to $DEST"

mkdir -p "$DEST" /usr/local/hestia/data/hestia-migrate /var/log/hestia-migrate
if command -v rsync >/dev/null 2>&1; then
	rsync -a --delete \
		--exclude '.git' \
		--exclude 'dist' \
		"$SRC/" "$DEST/"
else
	find "$DEST" -mindepth 1 -maxdepth 1 ! -name '.*' -exec rm -rf {} +
	cp -a "$SRC"/. "$DEST"/
	rm -rf "$DEST/.git" "$DEST/dist" 2>/dev/null || true
fi

chmod 755 "$DEST"
chmod 700 /usr/local/hestia/data/hestia-migrate
chmod 750 /var/log/hestia-migrate
find "$DEST/bin" -type f -exec chmod 755 {} \;
find "$DEST/lib" -type f -exec chmod 644 {} \;
find "$DEST/share" -type f -exec chmod 755 {} \;
chmod 755 "$DEST/hooks/"*.sh "$DEST/install.sh" "$DEST/uninstall.sh" 2>/dev/null || true
# Recommend sshpass for password bootstrap
if ! command -v sshpass >/dev/null 2>&1; then
	echo "NOTE: install sshpass for reliable SSH password auth: apt-get install -y sshpass"
fi

# CLI wrappers in Hestia bin
CMDS=(
	v-migrate-connect
	v-migrate-list-users
	v-migrate-analyze
	v-migrate-transfer
	v-migrate-start
	v-migrate-start-batch
	v-migrate-status
	v-migrate-verify
	v-migrate-inspect-job
	v-migrate-repair
	v-migrate-list-jobs
	v-migrate-wipe-session
	v-migrate-delete-job
)
for cmd in "${CMDS[@]}"; do
	ln -sfn "$DEST/bin/$cmd" "/usr/local/hestia/bin/$cmd"
	chmod 755 "$DEST/bin/$cmd"
done

# Sudoers for hestiaweb (panel PHP runs as hestiaweb)
SUDOERS=/etc/sudoers.d/hestia-migrate
cp "$DEST/sudo/hestia-migrate" "$SUDOERS"
if id www-data >/dev/null 2>&1; then
	sed -i 's/^hestiaweb ALL=/hestiaweb,www-data ALL=/' "$SUDOERS" || true
fi
chmod 440 "$SUDOERS"
visudo -cf "$SUDOERS" >/dev/null

# Web UI — symlink into Hestia web tree
WEB=/usr/local/hestia/web
mkdir -p "$WEB/migrate"
ln -sfn "$DEST/web/migrate/index.php" "$WEB/migrate/index.php"
ln -sfn "$DEST/web/migrate/api.php" "$WEB/migrate/api.php"
ln -sfn "$DEST/web/migrate/assets" "$WEB/migrate/assets"
mkdir -p "$WEB/templates/pages"
ln -sfn "$DEST/web/templates/pages/migrate.php" "$WEB/templates/pages/migrate.php"

# Hook: restore menu + plugins row after Hestia upgrades
HOOKS=/etc/hestiacp/hooks
mkdir -p "$HOOKS"
HOOK="$HOOKS/post_install.sh"
MARKER_BEGIN="# >>> hestia-migrate"
MARKER_END="# <<< hestia-migrate"
if [[ -f "$HOOK" ]]; then
	awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
		$0==b {skip=1; next}
		$0==e {skip=0; next}
		!skip {print}
	' "$HOOK" >"$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK"
else
	printf '#!/usr/bin/env bash\n' >"$HOOK"
fi
{
	echo "$MARKER_BEGIN"
	echo "/usr/local/hestia-migrate/hooks/post_install.sh || true"
	echo "$MARKER_END"
} >>"$HOOK"
chmod +x "$HOOK"

# Apply menu + Plugins patches now
"$DEST/hooks/post_install.sh"

echo "$VERSION" >"$DEST/.installed_version"
echo "==> hestia-migrate $VERSION installed"
echo "    Users → Import user   ·  /migrate/   ·  Settings → Configure → Plugins → User Import"
