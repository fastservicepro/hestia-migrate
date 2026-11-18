#!/usr/bin/env bash
# Emit JSON composition of one Hestia user (argument: USER)
set -euo pipefail
u=${1-}
[[ -n "$u" ]] || { echo '{"error":"user required"}'; exit 0; }
HESTIA=/usr/local/hestia
UD=$HESTIA/data/users/$u
[[ -d "$UD" ]] || { echo '{"error":"user not found"}'; exit 0; }

python3 - "$u" "$UD" "$HESTIA" <<'PY'
import json, os, re, sys, subprocess

user, ud, hestia = sys.argv[1], sys.argv[2], sys.argv[3]

def kv_file(path):
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            d = {}
            for m in re.finditer(r"([A-Z0-9_]+)='([^']*)'", line):
                d[m.group(1)] = m.group(2)
            if d:
                rows.append(d)
    return rows

def conf_value(path, key):
    if not os.path.isfile(path):
        return ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith(key + "="):
                return line.split("'", 2)[1] if "'" in line else line.split("=", 1)[1].strip()
    return ""

md5 = conf_value(f"{ud}/user.conf", "MD5")
if md5.startswith("$y$"):
    hash_type = "yescrypt"
elif md5.startswith("$6$"):
    hash_type = "sha512"
elif md5.startswith("$1$"):
    hash_type = "md5"
else:
    hash_type = "other"

try:
    home_mb = int(subprocess.check_output(["du", "-sm", f"/home/{user}"], text=True).split()[0])
except Exception:
    home_mb = 0

webs = []
for row in kv_file(f"{ud}/web.conf"):
    domain = row.get("DOMAIN", "")
    includes = []
    conf_dir = f"/home/{user}/conf/web/{domain}"
    if os.path.isdir(conf_dir):
        for name in os.listdir(conf_dir):
            path = os.path.join(conf_dir, name)
            if not os.path.isfile(path):
                continue
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            for m in re.finditer(r"include\s+([^;]+);", text):
                inc = m.group(1).strip().strip("'\"")
                if not inc.startswith(f"/home/{user}/"):
                    includes.append(inc)
    webs.append({
        "domain": domain,
        "alias": row.get("ALIAS", ""),
        "tpl": row.get("TPL", ""),
        "proxy": row.get("PROXY", ""),
        "backend": row.get("BACKEND", ""),
        "ssl": row.get("SSL", ""),
        "letsencrypt": row.get("LETSENCRYPT", ""),
        "ip": row.get("IP", ""),
        "external_includes": ";".join(includes),
    })

dbs = []
for row in kv_file(f"{ud}/db.conf"):
    dbs.append({
        "db": row.get("DB", ""),
        "dbuser": row.get("DBUSER", ""),
        "type": row.get("TYPE", ""),
        "charset": row.get("CHARSET", ""),
        "host": row.get("HOST", ""),
        "disk": row.get("U_DISK", "0"),
    })

mails = []
for row in kv_file(f"{ud}/mail.conf"):
    domain = row.get("DOMAIN", "")
    accounts = 0
    mc = f"{ud}/mail/{domain}.conf"
    if os.path.isfile(mc):
        accounts = sum(1 for line in open(mc, encoding="utf-8", errors="replace") if line.startswith("ACCOUNT="))
    mails.append({
        "domain": domain,
        "accounts": accounts,
        "catchall": row.get("CATCHALL", ""),
        "ssl": row.get("SSL", ""),
    })

dnss = []
for row in kv_file(f"{ud}/dns.conf"):
    dnss.append({
        "domain": row.get("DOMAIN", ""),
        "ip": row.get("IP", ""),
        "dnssec": row.get("DNSSEC", ""),
        "tpl": row.get("TPL", ""),
    })

cron_jobs = 0
cf = f"{ud}/cron.conf"
if os.path.isfile(cf):
    cron_jobs = sum(1 for line in open(cf, encoding="utf-8", errors="replace") if line.strip())

extras = []
home = f"/home/{user}"
if os.path.isdir(home):
    for name in os.listdir(home):
        if name not in ("conf", "web", "dns", "tmp", "mail"):
            extras.append(name)

pkg = conf_value(f"{ud}/user.conf", "PACKAGE")
pkg_exists = "yes" if os.path.isfile(f"{hestia}/data/packages/{pkg}.pkg") else "no"

out = {
    "user": user,
    "package": pkg,
    "package_exists": pkg_exists,
    "disk_mb": conf_value(f"{ud}/user.conf", "U_DISK") or "0",
    "home_mb": home_mb,
    "shell": conf_value(f"{ud}/user.conf", "SHELL"),
    "role": conf_value(f"{ud}/user.conf", "ROLE"),
    "twofa": conf_value(f"{ud}/user.conf", "TWOFA"),
    "hash_type": hash_type,
    "web": webs,
    "db": dbs,
    "mail": mails,
    "dns": dnss,
    "cron_jobs": cron_jobs,
    "extra_dirs": ",".join(extras),
    "templates": ",".join(sorted({w.get("tpl", "") for w in webs if w.get("tpl")})),
    "backends": ",".join(sorted({w.get("backend", "") for w in webs if w.get("backend")})),
    "proxies": ",".join(sorted({w.get("proxy", "") for w in webs if w.get("proxy")})),
}
print(json.dumps(out, ensure_ascii=False))
PY
