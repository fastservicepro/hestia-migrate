#!/usr/bin/env bash
# Shared helpers for hestia-migrate

set -o pipefail

MIGRATE_ROOT="${MIGRATE_ROOT:-/usr/local/hestia-migrate}"
MIGRATE_DATA="${MIGRATE_DATA:-/usr/local/hestia/data/hestia-migrate}"
MIGRATE_LOG_DIR="${MIGRATE_LOG_DIR:-/var/log/hestia-migrate}"
HESTIA_BIN="${HESTIA_BIN:-/usr/local/hestia/bin}"
HESTIA_DIR="${HESTIA_DIR:-/usr/local/hestia}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"

mkdir -p "$MIGRATE_DATA" "$MIGRATE_LOG_DIR" 2>/dev/null || true
chmod 700 "$MIGRATE_DATA" 2>/dev/null || true

json_escape() {
	local s=${1-}
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//$'\n'/\\n}
	s=${s//$'\r'/\\r}
	s=${s//$'\t'/\\t}
	printf '%s' "$s"
}

log_msg() {
	local level=$1
	shift
	local msg="$*"
	local ts
	ts=$(date '+%F %T')
	echo "[$ts] [$level] $msg" >>"$MIGRATE_LOG_DIR/migrate.log"
}

die_json() {
	local code=$1
	local msg=$2
	printf '{"ok":false,"error":"%s","code":%s}\n' "$(json_escape "$msg")" "$code"
	exit 1
}

require_root() {
	if [[ $(id -u) -ne 0 ]]; then
		die_json 1 "root required"
	fi
}

# Compare dotted versions: returns 0 if $1 >= $2
version_ge() {
	printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1 | grep -qx "$2"
}

# OS generation rank for migration direction checks
# Higher = newer. Cross-family same-generation allowed when stacks match.
os_rank() {
	local id=$1
	local ver=$2
	case "$id" in
	debian)
		case "$ver" in
		11) echo 11 ;;
		12) echo 12 ;;
		13) echo 13 ;;
		*) echo 0 ;;
		esac
		;;
	ubuntu)
		case "$ver" in
		22.04) echo 12 ;;
		24.04) echo 13 ;;
		26.04) echo 14 ;;
		*) echo 0 ;;
		esac
		;;
	*) echo 0 ;;
	esac
}

yescrypt_supported() {
	local id=$1
	local ver=$2
	local rank
	rank=$(os_rank "$id" "$ver")
	# Debian 11 cannot verify yescrypt created on newer systems as destination
	[[ "$rank" -ge 12 ]]
}

parse_kv() {
	# shellcheck disable=SC1090
	source <(grep -E '^[A-Z0-9_]+=' "$1" 2>/dev/null || true)
}

local_sys_json() {
	local os_id os_ver arch hestia_ver web proxy php_list db_engine db_ver
	local mail_sys dns_sys ftp_sys disk_free disk_total hestia_conf

	os_id=$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")
	os_ver=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-unknown}")
	arch=$(uname -m)
	hestia_conf=/usr/local/hestia/conf/hestia.conf
	hestia_ver=$(dpkg -l hestia 2>/dev/null | awk '/^ii/{print $3}' | head -n1)
	[[ -z "$hestia_ver" ]] && hestia_ver=$(grep -E '^VERSION=' "$hestia_conf" 2>/dev/null | cut -d= -f2 | tr -d "'" || true)

	web=$(grep -E '^WEB_SYSTEM=' "$hestia_conf" 2>/dev/null | cut -d= -f2 | tr -d "'" || true)
	proxy=$(grep -E '^PROXY_SYSTEM=' "$hestia_conf" 2>/dev/null | cut -d= -f2 | tr -d "'" || true)
	mail_sys=$(grep -E '^MAIL_SYSTEM=' "$hestia_conf" 2>/dev/null | cut -d= -f2 | tr -d "'" || true)
	dns_sys=$(grep -E '^DNS_SYSTEM=' "$hestia_conf" 2>/dev/null | cut -d= -f2 | tr -d "'" || true)
	ftp_sys=$(grep -E '^FTP_SYSTEM=' "$hestia_conf" 2>/dev/null | cut -d= -f2 | tr -d "'" || true)

	php_list=$(ls /etc/php 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
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

	disk_free=$(df -Pm /backup 2>/dev/null | awk 'NR==2{print $4}')
	[[ -z "$disk_free" ]] && disk_free=$(df -Pm / | awk 'NR==2{print $4}')
	disk_total=$(df -Pm /backup 2>/dev/null | awk 'NR==2{print $2}')
	[[ -z "$disk_total" ]] && disk_total=$(df -Pm / | awk 'NR==2{print $2}')

	local packages_dir="$HESTIA_DIR/data/packages"
	local templates_web="$HESTIA_DIR/data/templates/web"
	local php_backends
	php_backends=$(ls "$templates_web/php-fpm"/*.tpl 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.tpl$//' | tr '\n' ',' | sed 's/,$//' || true)

	printf '{'
	printf '"os_id":"%s","os_ver":"%s","arch":"%s",' "$(json_escape "$os_id")" "$(json_escape "$os_ver")" "$(json_escape "$arch")"
	printf '"hestia_ver":"%s","web_system":"%s","proxy_system":"%s",' "$(json_escape "$hestia_ver")" "$(json_escape "$web")" "$(json_escape "$proxy")"
	printf '"php_versions":"%s","php_backends":"%s",' "$(json_escape "$php_list")" "$(json_escape "$php_backends")"
	printf '"db_engine":"%s","db_ver":"%s",' "$(json_escape "$db_engine")" "$(json_escape "$db_ver")"
	printf '"mail_system":"%s","dns_system":"%s","ftp_system":"%s",' "$(json_escape "$mail_sys")" "$(json_escape "$dns_sys")" "$(json_escape "$ftp_sys")"
	printf '"disk_free_mb":%s,"disk_total_mb":%s,' "${disk_free:-0}" "${disk_total:-0}"
	printf '"hostname":"%s"' "$(json_escape "$(hostname -f 2>/dev/null || hostname)")"
	printf '}'
}

ssh_user_for_session() {
	local session=$1
	local f="$MIGRATE_DATA/sessions/$session/ssh_user"
	if [[ -f "$f" ]]; then
		cat "$f"
	else
		echo root
	fi
}

ssh_opts_for_session() {
	local session=$1
	local key="$MIGRATE_DATA/sessions/$session/id_ed25519"
	local port_file="$MIGRATE_DATA/sessions/$session/port"
	local host_file="$MIGRATE_DATA/sessions/$session/host"
	local port=22
	[[ -f "$port_file" ]] && port=$(cat "$port_file")
	local host ssh_user
	host=$(cat "$host_file")
	ssh_user=$(ssh_user_for_session "$session")
	echo "-i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20 -p $port ${ssh_user}@${host}"
}

remote_run() {
	local session=$1
	shift
	local ssh_user
	ssh_user=$(ssh_user_for_session "$session")
	# shellcheck disable=SC2046
	if [[ "$ssh_user" == "root" ]]; then
		ssh $(ssh_opts_for_session "$session") "$@"
	else
		# Non-root sessions must elevate for Hestia CLI / system files
		if [[ $# -eq 1 && "$1" == "bash -s" ]]; then
			ssh $(ssh_opts_for_session "$session") "sudo -n bash -s"
		elif [[ "$1" == "bash" && "$2" == "-s" ]]; then
			ssh $(ssh_opts_for_session "$session") "sudo -n bash -s"
		else
			ssh $(ssh_opts_for_session "$session") "sudo -n bash -lc $(printf '%q' "$*")"
		fi
	fi
}

session_dir() {
	echo "$MIGRATE_DATA/sessions/$1"
}

job_dir() {
	echo "$MIGRATE_DATA/jobs/$1"
}

# Best-effort wipe of a session's SSH keys (used by transfer cleanup hooks).
# Prefer calling /usr/local/hestia/bin/v-migrate-wipe-session for full JSON.
wipe_session_quiet() {
	local session=$1
	[[ -n "$session" ]] || return 0
	if [[ -x /usr/local/hestia/bin/v-migrate-wipe-session ]]; then
		/usr/local/hestia/bin/v-migrate-wipe-session "$session" >/dev/null 2>&1 || true
	elif [[ -x "$MIGRATE_ROOT/bin/v-migrate-wipe-session" ]]; then
		"$MIGRATE_ROOT/bin/v-migrate-wipe-session" "$session" >/dev/null 2>&1 || true
	fi
}
