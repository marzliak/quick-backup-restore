---
name: quick-backup-restore
description: "Time Clawshine — a simple but powerful time machine for OpenClaw. Hourly encrypted incremental snapshots of your agent's brain via restic. Use when the user asks to backup, restore, roll back, check status, or update."
metadata: { "openclaw": { "emoji": "⏱", "requires": { "bins": ["bash", "openssl", "curl", "jq"], "auto_install": ["restic", "yq"] }, "install": [{ "id": "setup", "kind": "shell", "label": "Run Quick Backup and Restore (time machine) setup", "command": "sudo bash {baseDir}/bin/setup.sh" }], "homepage": "https://github.com/marzliak/quick-backup-restore" } }
---

# ⏱🦞 Time Clawshine

**Your agent just nuked its own memory. Now what?**

You spent weeks training your OpenClaw agent — building memory, refining context, tuning personality. Then one bad session wipes it. Gone. And your last "real" backup? Yesterday. Maybe last week.

**Time Clawshine gives you a time machine.** Every hour, it silently takes an encrypted, incremental snapshot of your agent's brain — memory, sessions, config, everything. Only changed bytes are stored, so it runs in seconds and barely uses disk. When things break (and they will), you roll back to *exactly* the moment before it happened. Not yesterday. Not "the last backup." The exact hour.

**One command to install. Zero maintenance. Just works.**

```bash
sudo bash {baseDir}/bin/setup.sh
```

### Why this exists

| Problem | Without Time Clawshine | With Time Clawshine |
|---------|----------------------|---------------------|
| Agent overwrites MEMORY.md | Hope you saved a copy | `restore.sh "2h ago"` |
| Bad session corrupts context | Rebuild from scratch | Roll back one snapshot |
| "What changed?" | No idea | `restic diff` between any two snapshots |
| Disk fills up | Backup keeps growing | Dedup — only deltas stored |
| Something fails | You find out next week | Telegram ping in 60 seconds |

### What's under the hood

- **Restic** — battle-tested backup engine, AES-256 encryption, incremental deduplication
- **72 snapshots / 3 days** of history at hourly resolution (configurable)
- **Disk guard** — aborts before filling your disk, alerts via Telegram
- **Integrity checks** — automatic `restic check` every 24 backups
- **Daily digest** — Telegram summary with snapshot count, repo size, disk free
- **Update awareness** — checks ClawHub daily, never auto-updates
- **Status dashboard** — `bin/status.sh` for a full health check at a glance
- **Repository cleanup** — `bin/prune.sh` to manually reclaim disk space
- **Self-test** — `bin/test.sh` validates backup→restore→verify roundtrip
- **Guided setup** — agent reads `SETUP_GUIDE.md` and walks the user through every option
- **Dry-run mode** — `backup.sh --dry-run` to validate without writing
- **100% offline** — no data leaves your machine (Telegram and update check are opt-in)

---

## Technical reference

**Repository:** configured in `{baseDir}/config.yaml` (default: `/var/backups/quick-backup-restore`)
**Log:** `/var/log/quick-backup-restore.log` (rotated weekly via logrotate)
**Password file:** `/etc/quick-backup-restore.pass` (chmod 600 — **back this up separately**)

---

## When the user asks to set up or install Time Clawshine

**First, read `{baseDir}/SETUP_GUIDE.md` and walk the user through each step interactively.** The guide covers Telegram, frequency, retention, extra paths, disk safety, and repo location. Configure `config.yaml` based on their answers before running setup.

If the user wants a quick install without customization:

1. Check if already set up:
   ```bash
   restic -r /var/backups/quick-backup-restore --password-file /etc/quick-backup-restore.pass snapshots 2>/dev/null && echo "Already initialized"
   ```
2. Run setup:
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

**Restore by time (e.g. "roll back 2 hours"):**
```bash
sudo bash {baseDir}/bin/restore.sh "2h ago" --target /tmp/tc-restore
sudo bash {baseDir}/bin/restore.sh yesterday --target /tmp/tc-restore
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

## When the user asks to clean up or free disk space

```bash
sudo bash {baseDir}/bin/prune.sh
```

Options:
- `--keep-last 24` — keep only last 24 snapshots
- `--older-than 7d` — remove snapshots older than 7 days
- `--dry-run` — preview what would be removed
- `--yes` — skip confirmation prompt

---

## When the user asks to run a dry-run or test backup

**Dry-run (validates without writing):**
```bash
sudo bash {baseDir}/bin/backup.sh --dry-run
```

**Self-test (full backup→restore→verify roundtrip in temp directory):**
```bash
bash {baseDir}/bin/test.sh
```

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
