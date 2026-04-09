---
name: quick-backup-restore
description: "Time Clawshine — a simple but powerful time machine for OpenClaw. Hourly encrypted incremental snapshots of your agent's brain via restic. Use when the user asks to backup, restore, roll back, check status, or update."
metadata: { "openclaw": { "emoji": "⏱", "requires": { "bins": ["bash", "openssl", "curl", "jq"], "auto_install": ["restic", "yq"] }, "install": [{ "id": "setup", "kind": "shell", "label": "Run Quick Backup and Restore (time machine) setup", "command": "sudo bash {baseDir}/bin/setup.sh" }], "homepage": "https://github.com/marzliak/quick-backup-restore" } }
---

# ⏱🦞 Quick Backup and Restore (time machine)

Your OpenClaw agent builds memory, preferences, and context over time — and agents make mistakes. They overwrite things. They corrupt their own context. When that happens, you want to go back to *exactly* 2 hours ago, not yesterday's backup, not a full system restore.

This skill gives your agent hourly snapshots of its own brain. Restic-powered, encrypted, silent on success — and it pings you on Telegram only when something breaks.

## Overview

Quick Backup and Restore protects OpenClaw's runtime context (memory, sessions, config) with hourly snapshots. It runs automatically via cron. You can also trigger it manually or restore any point in the last 72 hours.

**Repository:** `{baseDir}/../../../var/backups/quick-backup-restore` (or as configured in `{baseDir}/config.yaml`)
**Log:** `/var/log/quick-backup-restore.log`
**Password file:** `/etc/quick-backup-restore.pass`

---

## When the user asks to set up or install Quick Backup and Restore (time machine)

1. Check if already set up:
   ```bash
   restic -r /var/backups/quick-backup-restore --password-file /etc/quick-backup-restore.pass snapshots 2>/dev/null && echo "Already initialized"
   ```
2. If not initialized, ask the user to fill in `{baseDir}/config.yaml` with their Telegram `bot_token` and `chat_id`, then run:
   ```bash
   sudo bash {baseDir}/bin/setup.sh
   ```
   For repo-only setup (no apt-get, no cron, no /usr/local/bin changes):
   ```bash
   sudo bash {baseDir}/bin/setup.sh --no-system-install
   ```
   For CI/automated setup (skip confirmation prompts):
   ```bash
   sudo bash {baseDir}/bin/setup.sh --assume-yes
   ```
3. Confirm setup succeeded by tailing the log:
   ```bash
   tail -5 /var/log/quick-backup-restore.log
   ```

---

## When the user asks to run a manual backup

```bash
sudo bash {baseDir}/bin/backup.sh
```

Then confirm with:
```bash
tail -5 /var/log/quick-backup-restore.log
```

---

## When the user asks to check backup status or history

Run the status dashboard:
```bash
sudo bash {baseDir}/bin/status.sh
```

Or show the last 20 log lines:
```bash
tail -20 /var/log/quick-backup-restore.log
```

List all snapshots (most recent first):
```bash
restic -r /var/backups/quick-backup-restore --password-file /etc/quick-backup-restore.pass snapshots
```

Show what changed between the two most recent snapshots:
```bash
SNAPS=$(restic -r /var/backups/quick-backup-restore --password-file /etc/quick-backup-restore.pass snapshots --json | jq -r '.[-2:][].id')
restic -r /var/backups/quick-backup-restore --password-file /etc/quick-backup-restore.pass diff $SNAPS
```

---

## When the user asks to restore or roll back

**Interactive restore (recommended — always dry-runs first):**
```bash
sudo bash {baseDir}/bin/restore.sh
```

**Restore a specific file from the latest snapshot:**
```bash
sudo bash {baseDir}/bin/restore.sh latest --file /root/.openclaw/workspace/MEMORY.md --target /tmp/tc-restore
# Preview the result, then move manually:
# cp /tmp/tc-restore/root/.openclaw/workspace/MEMORY.md /root/.openclaw/workspace/MEMORY.md
```

**Restore a specific snapshot by ID:**
```bash
sudo bash {baseDir}/bin/restore.sh <snapshot_id>
```

Always confirm with the user before executing a full restore to `/`.

---

## When the user asks to check repo integrity

```bash
restic -r /var/backups/quick-backup-restore --password-file /etc/quick-backup-restore.pass check
```

---

## When the user asks to change configuration

Edit `{baseDir}/config.yaml` with the requested changes (schedule, retention, paths, Telegram credentials), then re-run setup to apply:
```bash
sudo bash {baseDir}/bin/setup.sh
```

---

## When the user asks to customize backup paths

Run the local path analyzer (100% offline — no API calls, no data leaves the machine):
```bash
sudo bash {baseDir}/bin/customize.sh
```

This scans the system for:
- Extra paths worth backing up (e.g. `~/.ssh`, `~/.config`, custom scripts)
- Common junk patterns to exclude (e.g. `node_modules`, `*.log`, `cache/`)

Shows suggestions and asks for confirmation before changing `config.yaml`.

---

## Important notes

- **Silent by design:** cron runs every hour at :05 and logs to `/var/log/quick-backup-restore.log`. No output unless there is a failure.
- **Telegram fires only on failure.** If the user has not configured `bot_token` and `chat_id`, failures are logged only.
- **This is the time machine layer.** It protects against "the agent broke something in the last 3 days." It is NOT a disaster recovery backup — that should be handled by an off-VM backup (e.g. restic to a remote server).
- **Password:** The restic repository is AES-256 encrypted. The password is at `/etc/quick-backup-restore.pass` (chmod 600). Losing it means losing access to all snapshots.
- **Never commit `secrets.env` or `.pass` files to git.** They are excluded via `.gitignore`.

---

## When the user asks to check for updates

Run the status dashboard which includes update info:
```bash
sudo bash {baseDir}/bin/status.sh
```

Or check manually:
```bash
clawhub update quick-backup-restore
```

Note: `backup.sh` automatically checks for updates once per day (if `updates.check: true` in config). It logs a warning when a new version is available but never updates automatically.
