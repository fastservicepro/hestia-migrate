#!/usr/bin/env bash
# Remove hestia-migrate module
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
	echo "Run as root" >&2
	exit 1
fi

DEST=/usr/local/hestia-migrate
WEB=/usr/local/hestia/web

echo "==> Uninstalling hestia-migrate"

# Wipe any leftover session keys before removing the module
if [[ -x /usr/local/hestia/bin/v-migrate-wipe-session ]]; then
	for sdir in /usr/local/hestia/data/hestia-migrate/sessions/*; do
		[[ -d "$sdir" ]] || continue
		sid=$(basename "$sdir")
		/usr/local/hestia/bin/v-migrate-wipe-session "$sid" >/dev/null 2>&1 || true
	done
fi

for cmd in \
	v-migrate-connect \
	v-migrate-list-users \
	v-migrate-analyze \
	v-migrate-transfer \
	v-migrate-start \
	v-migrate-start-batch \
	v-migrate-status \
	v-migrate-verify \
	v-migrate-inspect-job \
	v-migrate-repair \
	v-migrate-list-jobs \
	v-migrate-wipe-session \
	v-migrate-delete-job
do
	rm -f "/usr/local/hestia/bin/$cmd"
done

rm -f /etc/sudoers.d/hestia-migrate
rm -rf "$WEB/migrate"
rm -f "$WEB/templates/pages/migrate.php"

# Remove menu + Plugins markers
if [[ -x "$DEST/hooks/remove_menu.sh" ]]; then
	"$DEST/hooks/remove_menu.sh" || true
fi

HOOK=/etc/hestiacp/hooks/post_install.sh
if [[ -f "$HOOK" ]]; then
	awk '
		$0=="# >>> hestia-migrate" {skip=1; next}
		$0=="# <<< hestia-migrate" {skip=0; next}
		!skip {print}
	' "$HOOK" >"$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK"
fi

# Keep session/job data unless --purge
if [[ "${1-}" == "--purge" ]]; then
	rm -rf /usr/local/hestia/data/hestia-migrate /var/log/hestia-migrate
fi

rm -rf "$DEST"
echo "==> hestia-migrate removed"
