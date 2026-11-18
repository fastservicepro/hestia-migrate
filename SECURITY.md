# Security Policy

## Supported versions

Please report issues against the latest release on the `main` branch.

## Reporting a vulnerability

Open a private report via GitHub Security Advisories on  
https://github.com/fastservicepro/hestia-migrate  
or create an issue **without** posting credentials, private keys, or customer data.

## Notes

- The module stores temporary SSH keys under `/usr/local/hestia/data/hestia-migrate/sessions/` and is designed to wipe them after use.
- If you suspect keys were left behind, run `v-migrate-wipe-session SESSION` or uninstall with `--purge` after wiping sessions.
