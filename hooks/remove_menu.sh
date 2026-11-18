#!/usr/bin/env bash
set -euo pipefail

strip_marker() {
	local path=$1
	local begin=$2
	local end=$3
	[[ -f "$path" ]] || return 0
	python3 - "$path" "$begin" "$end" <<'PY'
import re, sys
path, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()
pat = re.compile(
    r"\s*<!-- " + re.escape(begin) + r" -->.*?<!-- /" + re.escape(end) + r" -->\s*",
    re.S,
)
text2 = pat.sub("\n", text)
if text2 != text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text2)
PY
}

strip_marker /usr/local/hestia/web/templates/pages/list_user.php \
	hestia-migrate-import-btn hestia-migrate-import-btn

strip_marker /usr/local/hestia/web/templates/pages/edit_server.php \
	hestia-migrate-plugin hestia-migrate-plugin

# Save handler
EDIT_INDEX=/usr/local/hestia/web/edit/server/index.php
if [[ -f "$EDIT_INDEX" ]]; then
	python3 - "$EDIT_INDEX" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()
text2 = re.sub(
    r"\n\t// hestia-migrate-save\n.*?// /hestia-migrate-save\n",
    "\n",
    text,
    flags=re.S,
)
if text2 != text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text2)
PY
fi

CONF=/usr/local/hestia/conf/hestia.conf
if [[ -f "$CONF" ]] && grep -qE "^HESTIA_MIGRATE=" "$CONF"; then
	sed -i "/^HESTIA_MIGRATE=/d" "$CONF" || true
fi
