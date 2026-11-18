#!/usr/bin/env bash
# One-liner installer for hestia-migrate from GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/install-remote.sh | bash
#
# Optional:
#   bash install-remote.sh --ref v1.2.2
#   HESTIA_MIGRATE_REF=v1.2.2 bash install-remote.sh
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
	echo "Run as root: curl -fsSL ... | bash" >&2
	exit 1
fi

REPO_URL="${HESTIA_MIGRATE_REPO:-https://github.com/fastservicepro/hestia-migrate.git}"
REF="${HESTIA_MIGRATE_REF:-main}"
SRC_DIR="${HESTIA_MIGRATE_SRC:-/usr/local/src/hestia-migrate}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo) REPO_URL=$2; shift 2 ;;
	--ref) REF=$2; shift 2 ;;
	--src) SRC_DIR=$2; shift 2 ;;
	-h | --help)
		echo "Usage: $0 [--repo URL] [--ref BRANCH|TAG] [--src DIR]"
		exit 0
		;;
	*)
		echo "Unknown arg: $1" >&2
		exit 1
		;;
	esac
done

if [[ ! -d /usr/local/hestia ]]; then
	echo "Hestia Control Panel not found in /usr/local/hestia" >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq git sshpass python3 rsync ca-certificates curl >/dev/null || true

mkdir -p "$(dirname "$SRC_DIR")"
if [[ -d "$SRC_DIR/.git" ]]; then
	git -C "$SRC_DIR" fetch --tags --prune
	git -C "$SRC_DIR" checkout "$REF"
	git -C "$SRC_DIR" pull --ff-only origin "$REF" 2>/dev/null || true
else
	rm -rf "$SRC_DIR"
	git clone --branch "$REF" --depth 1 "$REPO_URL" "$SRC_DIR"
fi

bash "$SRC_DIR/install.sh"
