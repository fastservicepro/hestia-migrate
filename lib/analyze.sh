#!/usr/bin/env bash
# Verdict engine — reads session JSON files written by v-migrate-analyze

analyze_pair() {
	local session=$1
	local user=$2
	local sdir
	sdir=$(session_dir "$session")
	python3 - "$sdir/local.json" "$sdir/remote.json" "$sdir/user-$user.json" "$user" <<'PY'
import json, sys, os, re

local = json.loads(open(sys.argv[1], encoding="utf-8").read())
remote = json.loads(open(sys.argv[2], encoding="utf-8").read())
user = json.loads(open(sys.argv[3], encoding="utf-8").read())
username = sys.argv[4]

errors, warnings, plan = [], [], []

def ver_tuple(v):
    parts = []
    for p in (v or "0").replace("~", ".").split(".")[:3]:
        digits = "".join(c for c in p if c.isdigit())
        parts.append(int(digits or 0))
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)

def os_rank(os_id, os_ver):
    return {
        ("debian", "11"): 11, ("debian", "12"): 12, ("debian", "13"): 13,
        ("ubuntu", "22.04"): 12, ("ubuntu", "24.04"): 13, ("ubuntu", "26.04"): 14,
    }.get((os_id, str(os_ver)), 0)

src_rank = os_rank(remote.get("os_id"), remote.get("os_ver"))
dst_rank = os_rank(local.get("os_id"), local.get("os_ver"))
if dst_rank == 0:
    warnings.append(f"Destination OS {local.get('os_id')} {local.get('os_ver')} is outside the known Hestia matrix.")
if src_rank and dst_rank and dst_rank < src_rank:
    errors.append(
        f"Destination OS ({local.get('os_id')} {local.get('os_ver')}) is older than source "
        f"({remote.get('os_id')} {remote.get('os_ver')})."
    )
if ver_tuple(local.get("hestia_ver")) < ver_tuple(remote.get("hestia_ver")):
    errors.append(f"Destination Hestia {local.get('hestia_ver')} is older than source {remote.get('hestia_ver')}.")

ht = user.get("hash_type")
if ht == "yescrypt" and dst_rank < 12:
    errors.append("User password uses yescrypt; destination OS cannot verify it.")

if remote.get("db_engine") != local.get("db_engine") and remote.get("db_engine") != "none":
    errors.append(
        f"Database engine mismatch: source={remote.get('db_engine')} dest={local.get('db_engine')}."
    )
elif remote.get("db_engine") in ("mariadb", "mysql"):
    if ver_tuple(local.get("db_ver")) < ver_tuple(remote.get("db_ver")):
        errors.append(
            f"Destination {local.get('db_engine')} {local.get('db_ver')} is older than source {remote.get('db_ver')}."
        )

if (remote.get("web_system") or "") != (local.get("web_system") or "") or (
    remote.get("proxy_system") or ""
) != (local.get("proxy_system") or ""):
    warnings.append(
        f"Web stack differs (source {remote.get('web_system')}/{remote.get('proxy_system')} vs "
        f"dest {local.get('web_system')}/{local.get('proxy_system')}). Sites will be rebuilt."
    )

need = int(user.get("home_mb") or 0) * 2 + 512
free = int(local.get("disk_free_mb") or 0)
if free < need:
    errors.append(f"Not enough free disk on destination: need ~{need} MB, have {free} MB.")

hestia_users = "/usr/local/hestia/data/users"
if os.path.isdir(f"{hestia_users}/{username}"):
    errors.append(f"User '{username}' already exists on destination.")
elif os.path.exists(f"/home/{username}"):
    errors.append(f"Home directory /home/{username} already exists.")

existing_domains, existing_dbs = set(), set()
if os.path.isdir(hestia_users):
    for u in os.listdir(hestia_users):
        wc = f"{hestia_users}/{u}/web.conf"
        if os.path.isfile(wc):
            for line in open(wc, encoding="utf-8", errors="replace"):
                if "DOMAIN='" in line:
                    existing_domains.add(line.split("DOMAIN='", 1)[1].split("'", 1)[0])
                if "ALIAS='" in line:
                    for a in line.split("ALIAS='", 1)[1].split("'", 1)[0].split(","):
                        if a:
                            existing_domains.add(a)
        dc = f"{hestia_users}/{u}/db.conf"
        if os.path.isfile(dc):
            for line in open(dc, encoding="utf-8", errors="replace"):
                if "DB='" in line:
                    existing_dbs.add(line.split("DB='", 1)[1].split("'", 1)[0])

for site in user.get("web") or []:
    d = site.get("domain")
    if d in existing_domains:
        errors.append(f"Web domain '{d}' already exists on destination.")
    for a in (site.get("alias") or "").split(","):
        if a and a in existing_domains:
            errors.append(f"Web alias '{a}' already exists on destination.")
    if site.get("external_includes"):
        warnings.append(
            f"Domain {d} has includes outside home; NOT migrated: {site['external_includes']}"
        )
    plan.append({
        "object": f"web:{d}",
        "method": "Hestia archive stream → v-restore-user (new IP, chown new UID)",
        "notes": f"tpl={site.get('tpl')} backend={site.get('backend')} ssl={site.get('ssl')}",
    })

for db in user.get("db") or []:
    name = db.get("db")
    if name in existing_dbs:
        errors.append(f"Database '{name}' already exists on destination.")
    plan.append({
        "object": f"db:{name}",
        "method": "SQL dump in archive → rebuild_*_database using db.conf MD5 hash",
        "notes": f"type={db.get('type')} charset={db.get('charset')}",
    })

for m in user.get("mail") or []:
    plan.append({
        "object": f"mail:{m.get('domain')}",
        "method": "Maildir + account hashes → restore with user:mail ownership",
        "notes": f"accounts={m.get('accounts')}",
    })

for z in user.get("dns") or []:
    plan.append({
        "object": f"dns:{z.get('domain')}",
        "method": "Zone + DNSSEC; panel A/AAAA rewritten to destination IP",
        "notes": "Registrar / public NS NOT changed",
    })

plan.insert(0, {
    "object": f"user:{username}",
    "method": "user.conf MD5 → shadow; package .pkg copied if missing; new UID",
    "notes": f"hash={ht} package={user.get('package')}",
})
if int(user.get("cron_jobs") or 0) > 0:
    plan.append({
        "object": "cron",
        "method": "cron.conf + crontab; paths not silently rewritten",
        "notes": f"jobs={user.get('cron_jobs')}",
    })
if user.get("extra_dirs"):
    plan.append({
        "object": "home_extra",
        "method": "user_dir archive excluding conf/web/mail/tmp",
        "notes": user.get("extra_dirs"),
    })

def php_version_from_backend(backend):
    if not backend or backend == "default":
        return None
    m = re.search(r"PHP[-_]?(\d+)[._](\d+)", backend, re.I)
    if m:
        return f"{m.group(1)}.{m.group(2)}"
    return None

def stock_php_tpl(ver):
    return f"PHP-{ver.replace('.', '_')}"

def load_multiphp_supported():
    path = "/usr/local/hestia/install/upgrade/upgrade.conf"
    supported = set()
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return {"5.6", "7.0", "7.1", "7.2", "7.3", "7.4", "8.0", "8.1", "8.2", "8.3", "8.4", "8.5"}
    m = re.search(r"multiphp_v\s*=\s*\(([^)]*)\)", text)
    if m:
        for part in re.findall(r'"([^"]+)"', m.group(1)):
            supported.add(part)
    return supported or {"8.0", "8.1", "8.2", "8.3", "8.4", "8.5"}

def runtime_present(ver):
    if os.path.isdir(f"/etc/php/{ver}/fpm"):
        return True
    if os.path.isfile(f"/etc/init.d/php{ver}-fpm"):
        return True
    # Panel probe may list bare versions under php_versions
    for p in filter(None, (local.get("php_versions") or "").split(",")):
        if p == ver or p.startswith(ver):
            return True
    return False

def template_present(name):
    if not name:
        return True
    base = "/usr/local/hestia/data/templates/web/php-fpm"
    return os.path.isfile(f"{base}/{name}.tpl")

supported_php = load_multiphp_supported()
installed_php = sorted({
    p for p in filter(None, (local.get("php_versions") or "").split(","))
    if re.match(r"^\d+\.\d+", p)
})
# Also detect from /etc/php
if os.path.isdir("/etc/php"):
    for name in os.listdir("/etc/php"):
        if re.match(r"^\d+\.\d+$", name) and os.path.isdir(f"/etc/php/{name}/fpm"):
            if name not in installed_php:
                installed_php.append(name)
installed_php = sorted(set(installed_php), key=lambda v: ver_tuple(v))

php_items = []
seen_backends = set()
for b in filter(None, (user.get("backends") or "").split(",")):
    if b in seen_backends:
        continue
    seen_backends.add(b)
    ver = php_version_from_backend(b)
    tpl_ok = template_present(b) or (ver and template_present(stock_php_tpl(ver)))
    if not ver:
        php_items.append({
            "backend": b,
            "version": "",
            "runtime": "n/a",
            "template": "present" if template_present(b) else "missing",
            "installable": False,
            "action": "ok" if template_present(b) else "template_missing",
        })
        if not template_present(b):
            warnings.append(f"Web template/backend '{b}' missing locally; will copy from source if present.")
        continue
    rt_ok = runtime_present(ver)
    installable = ver in supported_php
    if rt_ok:
        action = "ok"
        if not tpl_ok:
            action = "template_missing"
            warnings.append(
                f"PHP {ver} runtime is installed but backend template '{b}' is missing; "
                f"will copy from source if present."
            )
    elif installable:
        action = "needs_install"
        warnings.append(
            f"PHP {ver} runtime is not installed (backend '{b}'). "
            f"Confirm software install before import, or remap to an installed version."
        )
    else:
        action = "needs_remap"
        warnings.append(
            f"PHP {ver} is required by backend '{b}' but cannot be installed on this Hestia build "
            f"and is not present. You must remap it to an installed PHP before import."
        )
    php_items.append({
        "backend": b,
        "version": ver,
        "runtime": "present" if rt_ok else "missing",
        "template": "present" if tpl_ok else "missing",
        "installable": installable and not rt_ok,
        "action": action,
    })

packages_to_copy = []
pkg = user.get("package")
if pkg and not os.path.isfile(f"/usr/local/hestia/data/packages/{pkg}.pkg"):
    packages_to_copy.append(pkg)
    warnings.append(f"Package '{pkg}' missing locally; will be copied from source.")

templates_to_copy = sorted({
    item["backend"] for item in php_items
    if item.get("template") == "missing" and item.get("backend")
})

software = {
    "php": php_items,
    "php_installed": installed_php,
    "php_supported": sorted(supported_php, key=lambda v: ver_tuple(v)),
    "packages_to_copy": packages_to_copy,
    "templates_to_copy": templates_to_copy,
    "needs_install": sorted({i["version"] for i in php_items if i.get("action") == "needs_install"}),
    "needs_remap": sorted({i["version"] for i in php_items if i.get("action") == "needs_remap"}),
}

if user.get("twofa"):
    warnings.append("2FA secret migrates with user.conf; keep authenticator app.")

warnings.append("Let's Encrypt stays off until you confirm DNS points here.")
warnings.append("Source account is left running until you change DNS at the registrar.")
warnings.append(
    "MultiPHP checkboxes in Server settings reflect domain backends after import; "
    "they are not proof that PHP packages are installed."
)

verdict = "blocked" if errors else ("warn" if warnings else "ok")
print(json.dumps({
    "ok": True,
    "verdict": verdict,
    "user": username,
    "source": remote,
    "destination": local,
    "composition": user,
    "plan": plan,
    "errors": errors,
    "warnings": warnings,
    "software": software,
    "disk_required_mb": need,
    "disk_free_mb": free,
}, ensure_ascii=False))
PY
}
