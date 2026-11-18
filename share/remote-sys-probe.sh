#!/usr/bin/env bash
set -euo pipefail
os_id=$(. /etc/os-release; echo "$ID")
os_ver=$(. /etc/os-release; echo "$VERSION_ID")
arch=$(uname -m)
hestia_conf=/usr/local/hestia/conf/hestia.conf
hestia_ver=$(dpkg -l hestia 2>/dev/null | awk '/^ii/{print $3}' | head -n1)
web=$(grep -E '^WEB_SYSTEM=' "$hestia_conf" | cut -d= -f2 | tr -d "'")
proxy=$(grep -E '^PROXY_SYSTEM=' "$hestia_conf" | cut -d= -f2 | tr -d "'")
mail_sys=$(grep -E '^MAIL_SYSTEM=' "$hestia_conf" | cut -d= -f2 | tr -d "'")
dns_sys=$(grep -E '^DNS_SYSTEM=' "$hestia_conf" | cut -d= -f2 | tr -d "'")
ftp_sys=$(grep -E '^FTP_SYSTEM=' "$hestia_conf" | cut -d= -f2 | tr -d "'")
php_list=$(ls /etc/php 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
php_backends=$(ls /usr/local/hestia/data/templates/web/php-fpm/*.tpl 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.tpl$//' | tr '\n' ',' | sed 's/,$//' || true)
if command -v mariadb >/dev/null 2>&1 || [[ -f /usr/bin/mariadbd ]]; then
	db_engine=mariadb
	db_ver=$(mariadb --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
elif command -v mysql >/dev/null 2>&1; then
	db_engine=mysql
	db_ver=$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
else
	db_engine=none
	db_ver=
fi
disk_free=$(df -Pm / | awk 'NR==2{print $4}')
printf '{"os_id":"%s","os_ver":"%s","arch":"%s","hestia_ver":"%s","web_system":"%s","proxy_system":"%s","php_versions":"%s","php_backends":"%s","db_engine":"%s","db_ver":"%s","mail_system":"%s","dns_system":"%s","ftp_system":"%s","disk_free_mb":%s,"hostname":"%s"}' \
	"$os_id" "$os_ver" "$arch" "$hestia_ver" "$web" "$proxy" "$php_list" "$php_backends" "$db_engine" "$db_ver" "$mail_sys" "$dns_sys" "$ftp_sys" "${disk_free:-0}" "$(hostname -f 2>/dev/null || hostname)"
