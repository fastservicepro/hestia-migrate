#!/usr/bin/env bash
# Collect destination-facing facts about a remote Hestia host.
# Must never abort on missing optional fields — connect treats any non-zero
# exit as "remote probe failed".
set -uo pipefail

hestia_conf=/usr/local/hestia/conf/hestia.conf

kv() {
	local key=$1
	local val=
	if [[ -f "$hestia_conf" ]]; then
		val=$(grep -E "^${key}=" "$hestia_conf" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d "'" || true)
	fi
	printf '%s' "$val"
}

os_id=unknown
os_ver=unknown
if [[ -f /etc/os-release ]]; then
	# shellcheck disable=SC1091
	os_id=$(. /etc/os-release; echo "${ID:-unknown}")
	# shellcheck disable=SC1091
	os_ver=$(. /etc/os-release; echo "${VERSION_ID:-unknown}")
fi
arch=$(uname -m 2>/dev/null || echo unknown)

hestia_ver=
if command -v dpkg >/dev/null 2>&1; then
	hestia_ver=$(dpkg -l hestia 2>/dev/null | awk '/^ii/{print $3}' | head -n1 || true)
fi
if [[ -z "$hestia_ver" ]]; then
	hestia_ver=$(kv VERSION)
fi

web=$(kv WEB_SYSTEM)
proxy=$(kv PROXY_SYSTEM)
mail_sys=$(kv MAIL_SYSTEM)
dns_sys=$(kv DNS_SYSTEM)
ftp_sys=$(kv FTP_SYSTEM)

php_list=
if [[ -d /etc/php ]]; then
	php_list=$(ls /etc/php 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
fi

php_backends=
if ls /usr/local/hestia/data/templates/web/php-fpm/*.tpl >/dev/null 2>&1; then
	php_backends=$(ls /usr/local/hestia/data/templates/web/php-fpm/*.tpl 2>/dev/null \
		| xargs -n1 basename 2>/dev/null \
		| sed 's/\.tpl$//' \
		| tr '\n' ',' \
		| sed 's/,$//' || true)
fi

db_engine=none
db_ver=
if command -v mariadb >/dev/null 2>&1 || [[ -f /usr/bin/mariadbd ]]; then
	db_engine=mariadb
	db_ver=$(mariadb --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
elif command -v mysql >/dev/null 2>&1; then
	db_engine=mysql
	db_ver=$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
fi

disk_free=$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')
hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown)

# Escape for JSON string values (minimal)
je() {
	printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null \
		|| printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

printf '{"os_id":"%s","os_ver":"%s","arch":"%s","hestia_ver":"%s","web_system":"%s","proxy_system":"%s","php_versions":"%s","php_backends":"%s","db_engine":"%s","db_ver":"%s","mail_system":"%s","dns_system":"%s","ftp_system":"%s","disk_free_mb":%s,"hostname":"%s"}' \
	"$(je "$os_id")" \
	"$(je "$os_ver")" \
	"$(je "$arch")" \
	"$(je "$hestia_ver")" \
	"$(je "$web")" \
	"$(je "$proxy")" \
	"$(je "$php_list")" \
	"$(je "$php_backends")" \
	"$(je "$db_engine")" \
	"$(je "$db_ver")" \
	"$(je "$mail_sys")" \
	"$(je "$dns_sys")" \
	"$(je "$ftp_sys")" \
	"${disk_free:-0}" \
	"$(je "$hostname")"
