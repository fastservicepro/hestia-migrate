#!/usr/bin/env bash
# Inject User Import Yes/No into Hestia Settings → Plugins + save handler.
set -euo pipefail

EDIT_SERVER=/usr/local/hestia/web/templates/pages/edit_server.php
EDIT_INDEX=/usr/local/hestia/web/edit/server/index.php
MODULE=/usr/local/hestia-migrate

[[ -f "$EDIT_SERVER" ]] || exit 0

CONF=/usr/local/hestia/conf/hestia.conf
if [[ -f "$CONF" ]]; then
	if ! grep -qE "^HESTIA_MIGRATE=" "$CONF" 2>/dev/null; then
		echo "HESTIA_MIGRATE='true'" >>"$CONF"
	else
		sed -i "s/^HESTIA_MIGRATE='yes'/HESTIA_MIGRATE='true'/" "$CONF" || true
		sed -i 's/^HESTIA_MIGRATE="yes"/HESTIA_MIGRATE="true"/' "$CONF" || true
	fi
	# Fresh module install / upgrade: enable plugin (user can still set No in Settings → Plugins).
	if [[ "${HESTIA_MIGRATE_ENABLE_DEFAULT:-}" == "1" ]]; then
		if [[ -x /usr/local/hestia/bin/v-change-sys-config-value ]]; then
			/usr/local/hestia/bin/v-change-sys-config-value HESTIA_MIGRATE true >/dev/null 2>&1 || true
		else
			sed -i "s/^HESTIA_MIGRATE=.*/HESTIA_MIGRATE='true'/" "$CONF" 2>/dev/null || true
		fi
	fi
fi

python3 - "$EDIT_SERVER" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()

snippet = '''\t\t\t\t\t<!-- hestia-migrate-plugin -->
\t\t\t\t\t<div class="u-mb10">
\t\t\t\t\t\t<label for="v_hestia_migrate" class="form-label">
\t\t\t\t\t\t\t<?= tohtml( _("User Import (Hestia↔Hestia)")) ?>
\t\t\t\t\t\t</label>
\t\t\t\t\t\t<select class="form-select" name="v_hestia_migrate" id="v_hestia_migrate">
\t\t\t\t\t\t\t<option value="false" <?= tohtml((($_SESSION["HESTIA_MIGRATE"] ?? "true") === "false") ? "selected" : "") ?>>
\t\t\t\t\t\t\t\t<?= tohtml( _("No")) ?>
\t\t\t\t\t\t\t</option>
\t\t\t\t\t\t\t<option value="true" <?= tohtml((($_SESSION["HESTIA_MIGRATE"] ?? "true") === "true" || ($_SESSION["HESTIA_MIGRATE"] ?? "") === "yes") ? "selected" : "") ?>>
\t\t\t\t\t\t\t\t<?= tohtml( _("Yes")) ?>
\t\t\t\t\t\t\t</option>
\t\t\t\t\t\t</select>
\t\t\t\t\t</div>
\t\t\t\t\t<!-- /hestia-migrate-plugin -->
'''

text = re.sub(
    r"\s*<!-- hestia-migrate-plugin -->.*?<!-- /hestia-migrate-plugin -->\s*",
    "\n",
    text,
    flags=re.S,
)

needle = '<?= tohtml( _("Plugins")) ?>'
idx = text.find(needle)
if idx < 0:
    sys.exit(0)
content = text.find("box-collapse-content", idx)
if content < 0:
    sys.exit(0)
gt = text.find(">", content)
if gt < 0:
    sys.exit(0)
text = text[: gt + 1] + "\n" + snippet + text[gt + 1 :]
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY

if [[ -f "$EDIT_INDEX" ]]; then
	python3 - "$EDIT_INDEX" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()

text = re.sub(
    r"\n\t// hestia-migrate-save\n.*?// /hestia-migrate-save\n",
    "\n",
    text,
    flags=re.S,
)

block = '''
\t// hestia-migrate-save
\tif (empty($_SESSION["error_msg"]) && isset($_POST["v_hestia_migrate"])) {
\t\t$v_hestia_migrate = $_POST["v_hestia_migrate"] === "true" ? "true" : "false";
\t\t$cur = $_SESSION["HESTIA_MIGRATE"] ?? "";
\t\tif ($cur === "yes") {
\t\t\t$cur = "true";
\t\t}
\t\tif ($v_hestia_migrate !== $cur) {
\t\t\texec(
\t\t\t\tHESTIA_CMD .
\t\t\t\t\t"v-change-sys-config-value HESTIA_MIGRATE " .
\t\t\t\t\tquoteshellarg($v_hestia_migrate),
\t\t\t\t$output,
\t\t\t\t$return_var,
\t\t\t);
\t\t\tcheck_return_code($return_var, $output);
\t\t\tunset($output);
\t\t\tif (empty($_SESSION["error_msg"])) {
\t\t\t\t$_SESSION["HESTIA_MIGRATE"] = $v_hestia_migrate;
\t\t\t}
\t\t}
\t}
\t// /hestia-migrate-save
'''

for anchor in (
    "// Enable/Disable Quick App Installer",
    "// Set File Manager support",
):
    idx = text.find(anchor)
    if idx >= 0:
        text = text[:idx] + block + "\n\t" + text[idx:]
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        break
PY
fi

exit 0
