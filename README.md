# hestia-migrate
<img width="1060" height="595" alt="hestia-migrate" src="https://github.com/user-attachments/assets/2deb8fd7-c635-48de-bef4-05b394757885" />

**User import module for [Hestia Control Panel](https://hestiacp.com/)** — move accounts between your own Hestia servers from the panel (SSH to the source, analyze, backup/restore via official Hestia tools). No telemetry; passwords are not stored.

Latest release: **Version 1.3.0**

[GitHub](https://github.com/fastservicepro/hestia-migrate) · [Releases](https://github.com/fastservicepro/hestia-migrate/releases) · [Issues](https://github.com/fastservicepro/hestia-migrate/issues) · [Security](SECURITY.md)

---

## Requirements

**Destination (install here):** HestiaCP, Debian 12/13 or Ubuntu 22.04/24.04/26.04, root. `install.sh` installs `openssh-client`, **`sshpass`**, `python3`, `rsync`, `curl`, `ca-certificates`, `xxd`.

**Source:** HestiaCP; SSH as `root` or passwordless sudo; destination must reach source over SSH.

Install on the **new** server. Source stays online until you change DNS.

---

## Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/install-remote.sh | bash
```

Then **Users → Import user** or `/migrate/`. User Import is **enabled by default** (toggle under **Settings → Configure → Plugins**).

Pin a release: `bash install-remote.sh --ref v1.3.0` or download [hestia-migrate.zip](https://github.com/fastservicepro/hestia-migrate/releases/latest/download/hestia-migrate.zip) and run `bash install.sh`.

---

## Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/install-remote.sh | bash
```

```bash
echo -n "installed: "; cat /usr/local/hestia-migrate/VERSION
echo -n "github:    "; curl -fsSL https://raw.githubusercontent.com/fastservicepro/hestia-migrate/main/VERSION
```

Re-running install is idempotent and re-enables User Import unless you turn it off in Plugins.

---

## Uninstall

```bash
bash /usr/local/hestia-migrate/uninstall.sh
```

With session/job data:

```bash
bash /usr/local/hestia-migrate/uninstall.sh --purge
```

---

## License

MIT — see [LICENSE](LICENSE). Third-party module; not affiliated with hestiacp.com.