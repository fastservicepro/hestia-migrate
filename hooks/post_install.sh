#!/usr/bin/env bash
# Re-apply menu entry + Plugins toggle after Hestia package upgrades overwrite templates.
set -euo pipefail

LIST_USER=/usr/local/hestia/web/templates/pages/list_user.php
MARKER="hestia-migrate-import-btn"
MODULE=/usr/local/hestia-migrate

if [[ ! -f "$LIST_USER" ]]; then
	exit 0
fi

WEB=/usr/local/hestia/web
mkdir -p "$WEB/migrate" "$WEB/templates/pages"
ln -sfn "$MODULE/web/migrate/index.php" "$WEB/migrate/index.php"
ln -sfn "$MODULE/web/migrate/api.php" "$WEB/migrate/api.php"
ln -sfn "$MODULE/web/migrate/assets" "$WEB/migrate/assets"
ln -sfn "$MODULE/web/templates/pages/migrate.php" "$WEB/templates/pages/migrate.php"

for cmd in \
	v-migrate-connect \
	v-migrate-list-users \
	v-migrate-analyze \
	v-migrate-transfer \
	v-migrate-start \
	v-migrate-start-batch \
	v-migrate-batch-status \
	v-migrate-prep-php \
	v-migrate-status \
	v-migrate-verify \
	v-migrate-inspect-job \
	v-migrate-repair \
	v-migrate-list-jobs \
	v-migrate-jobs-for-users \
	v-migrate-wipe-session \
	v-migrate-delete-job
do
	[[ -x "$MODULE/bin/$cmd" ]] && ln -sfn "$MODULE/bin/$cmd" "/usr/local/hestia/bin/$cmd"
done

if [[ -x "$MODULE/hooks/patch_plugins.sh" ]]; then
	"$MODULE/hooks/patch_plugins.sh" || true
fi

# Always refresh Users toolbar button (idempotent replace)
python3 - "$LIST_USER" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()

# Strip any previous marker (including broken inserts outside toolbar-buttons)
text = re.sub(
    r"\s*<!-- hestia-migrate-import-btn -->.*?<!-- /hestia-migrate-import-btn -->\s*",
    "\n",
    text,
    flags=re.S,
)

snippet = '''\t\t\t<!-- hestia-migrate-import-btn -->
\t\t\t<?php
\t\t\t$hmig_on = (($_SESSION["HESTIA_MIGRATE"] ?? "true") === "true" || ($_SESSION["HESTIA_MIGRATE"] ?? "") === "yes");
\t\t\tif ($_SESSION["userContext"] === "admin" && empty($_SESSION["look"]) && $hmig_on):
\t\t\t?>
\t\t\t\t<a class="button button-secondary" href="/migrate/">
\t\t\t\t\t<i class="fas fa-people-arrows icon-purple"></i><?= _("Import user") ?>
\t\t\t\t</a>
\t\t\t<?php endif; ?>
\t\t\t<!-- /hestia-migrate-import-btn -->
'''

# Insert as first control inside toolbar-buttons (before Add User)
needle = 'href="/add/user/"'
idx = text.find(needle)
if idx < 0:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    sys.exit(0)

# Find opening <div class="toolbar-buttons"> that contains add/user
tb = text.rfind("toolbar-buttons", 0, idx)
if tb < 0:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    sys.exit(0)
gt = text.find(">", tb)
if gt < 0:
    sys.exit(1)
text = text[: gt + 1] + "\n" + snippet + text[gt + 1 :]
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY

exit 0
