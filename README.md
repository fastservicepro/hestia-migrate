# hestia-migrate
<img width="1060" height="595" alt="hestia-migrate" src="https://github.com/user-attachments/assets/2deb8fd7-c635-48de-bef4-05b394757885" />

**User import module for [Hestia Control Panel](https://hestiacp.com/)** — migrate accounts from one Hestia server to another without manual backup / scp / restore in a terminal.

Latest release: **Version 1.2.9**

Please go easy on this project — this is my first publicly shared code. I built it for myself because backing up and moving Hestia users only through the terminal was painfully inconvenient. The module is meant simply to make transferring users between your own Hestia servers easier. If it’s useful to anyone else, I’m glad. Contributions and improvements are very welcome.

[GitHub](https://github.com/fastservicepro/hestia-migrate) · [Releases](https://github.com/fastservicepro/hestia-migrate/releases) · [Issues](https://github.com/fastservicepro/hestia-migrate/issues)

---

## What it does

From the **destination** panel an administrator:

1. Connects to a **source** Hestia server over SSH (password used once, not stored)
2. Selects one or more Hestia users
3. Reviews a full compatibility analysis (OS, Hestia, PHP, database, disk, conflicts)
4. Imports web, mail, DNS, databases, cron and home files via official `v-backup-user` / `v-restore-user`
5. Verifies sites on the new IP, then switches DNS and optionally issues Let's Encrypt

Temporary SSH keys are wiped after import or when you disconnect. Job history can be deleted together with leftover archives under `/backup`.

---

## Requirements

### Destination server (where you install the module)

- Hestia Control Panel already installed
- Debian 12 / 13 or Ubuntu 22.04 / 24.04 / 26.04
- Root access
- Packages installed automatically by `install.sh`: `openssh-client`, **`sshpass`** (required), `python3`, `rsync`, `curl`, `ca-certificates`, `xxd`

### Source server (the old panel you import from)

- Hestia Control Panel
- SSH as `root`, or a user with **passwordless sudo**
- Outbound SSH from destination → source must be allowed

**Notes**

- Install on the **new** server (destination), not on the source.
- Source accounts stay online until you change DNS at the registrar.

---

## Installing hestia-migrate

### Step 1: Log in as root

```bash
ssh root@your.destination.server
```

### Step 2: One-line install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/install-remote.sh | bash
```

If `curl` fails with an SSL error:

```bash
apt-get update && apt-get install -y ca-certificates curl
```

### Step 3: Open the panel

- **Users → Import user**, or open `/migrate/`
- The module is **enabled by default** after `install.sh` (Users toolbar shows **Import user**). Turn it off under **Settings → Configure → Plugins → User Import (Hestia↔Hestia)** if you do not need it.

---

## Alternative install methods

### Clone with git

```bash
cd /usr/local/src
git clone https://github.com/fastservicepro/hestia-migrate.git
cd hestia-migrate
bash install.sh
```

### Install from a release zip

Use the **stable** asset name (always the newest release):

```bash
cd /usr/local/src
wget -O hestia-migrate.zip https://github.com/fastservicepro/hestia-migrate/releases/latest/download/hestia-migrate.zip
unzip -o hestia-migrate.zip -d hestia-migrate
cd hestia-migrate
bash install.sh
```

Pin a specific version if needed: `.../download/hestia-migrate-1.2.8.zip`

`install.sh` / `install-remote.sh` install **`sshpass` and the other required packages** automatically. Without `sshpass`, Connect cannot reliably push a temporary SSH key to the source server.

---

## How to upgrade

GitHub does **not** push updates to your server. You re-run install when you want a newer version.

**Recommended (always tracks latest `main` / newest release tag you pull):**

```bash
curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/install-remote.sh | bash
```

Or from an existing clone:

```bash
cd /usr/local/src/hestia-migrate
git fetch --tags
git pull --ff-only
bash install.sh
```

**Check whether an update exists**

```bash
echo -n "installed: "; cat /usr/local/hestia-migrate/VERSION
echo -n "github:    "; curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/VERSION
```

If `github` is newer than `installed`, run the upgrade command above.

`install.sh` is idempotent: it refreshes files, sudoers, the Users button, and the Plugins Yes/No control. **Re-running install also turns User Import on** (unless you disable it again in Plugins). After a Hestia package upgrade, `/etc/hestiacp/hooks/post_install.sh` re-applies the UI patches automatically.

---

## PHP versions before import (1.2.6+)

Analysis compares each account’s PHP-FPM **backend** (e.g. `PHP-8_3`) with runtimes actually present under `/etc/php/*/fpm`, not merely what is ticked in **Server settings → Configure → MultiPHP**. Those checkboxes only mirror domain backends in the panel; they do **not** prove that `php8.3-fpm` packages exist.

When a required PHP version can be installed on this Hestia build, the wizard offers **Install the listed PHP versions…** and runs `v-add-web-php` once for the whole batch **before** the first `v-backup-user`. When a version is too old for your Hestia (e.g. PHP 5.6 on a new server), choose a **remap target** per version; domains are switched with `v-change-web-domain-backend-tpl` after restore.

Order of operations: **Analyze → confirm PHP install/remap → prep (`v-migrate-prep-php`) → sequential user transfer**.

---

## Versioning on GitHub (how “latest” works)

| Piece | Role |
|-------|------|
| File `VERSION` in the repo | Current version string (e.g. `1.2.3`) |
| Git tag `v1.2.3` | Marks that commit as a release |
| GitHub **Release** for that tag | Page people see under Releases; can attach zip files |
| URL `.../releases/latest/...` | GitHub alias → **newest non-prerelease** Release |
| Asset `hestia-migrate.zip` | **Stable filename** every release — `latest/download/hestia-migrate.zip` always works |
| Asset `hestia-migrate-1.2.3.zip` | Optional pinned copy for that version only |

So: publish Release **v1.2.3**, attach **both** zips (same contents). Next time you ship 1.2.4, attach `hestia-migrate.zip` again (overwrites “latest” link target) plus `hestia-migrate-1.2.4.zip`.

---

## Uninstall

```bash
bash /usr/local/hestia-migrate/uninstall.sh
```

Purge job / session data as well:

```bash
bash /usr/local/hestia-migrate/uninstall.sh --purge
```

Uninstall wipes any remaining temporary SSH keys first.

---

## Using the wizard

1. **Server** — hostname/IP, SSH port, login, password  
2. **Users** — multi-select accounts on the source  
3. **Analysis** — verdict `ok` / `warn` / `blocked`; batch summary of PHP versions to install or remap  
4. **Transfer** — optional PHP prep → backup → stream → restore; LE held until DNS is ready  
5. **Repair** — finish partial imports from the local archive  
6. **DNS** — probe domains on the new IP; checklist for registrar A records  
7. **History** — list past jobs; **Delete** removes history + leftover `/backup` archive (does **not** delete the Hestia user)

---

## CLI

```bash
v-migrate-connect HOST [PORT] PASSWORD_FILE [SSH_USER]
v-migrate-list-users SESSION
v-migrate-analyze SESSION USER
v-migrate-start SESSION USER [yes]
v-migrate-start-batch SESSION yes|no yes|no INSTALL_PHP REMAP_PHP USER [USER…]
v-migrate-prep-php VERSION [VERSION…]
v-migrate-batch-status [BATCH_ID]
v-migrate-status JOB
v-migrate-list-jobs [LIMIT]
v-migrate-inspect-job JOB
v-migrate-repair JOB ACTION
v-migrate-verify JOB [yes]
v-migrate-wipe-session SESSION
v-migrate-delete-job JOB
```

---

## Layout on disk

| Path | Role |
|------|------|
| `/usr/local/hestia-migrate` | Module root |
| `/usr/local/hestia/bin/v-migrate-*` | CLI symlinks |
| `/usr/local/hestia/web/migrate/` | Panel UI |
| `/usr/local/hestia/data/hestia-migrate/` | Sessions & jobs (local only) |
| `/etc/hestiacp/hooks/post_install.sh` | Re-applies UI after Hestia upgrades |

---

## Privacy & security

- **No telemetry**, analytics, or phone-home.
- Network use is only what you start: SSH to the source host **you enter**, plus local HTTP probes to **this server’s IP** during verify.
- Passwords are shredded after the temporary key is installed; session keys are wiped after import / disconnect.
- Job history never stores passwords or private keys.

---

## Issues & support

- Bugs and feature requests: [GitHub Issues](https://github.com/fastservicepro/hestia-migrate/issues)
- Please include destination OS, Hestia version, and whether the failure happened at connect / analyze / transfer / restore.

This is a **third-party module**, not part of the official HestiaCP distribution. For general Hestia help use the [Hestia forum](https://forum.hestiacp.com/).

---

## License

MIT — see [LICENSE](LICENSE).

Hestia Control Panel is a separate project (GPL-3.0). This module is not affiliated with or endorsed by hestiacp.com; “Hestia” / “HestiaCP” names refer to compatibility with that panel.
