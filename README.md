# ⏱🪞 Time Clawshine

[![CI](https://github.com/marzliak/quick-backup-restore/actions/workflows/ci.yml/badge.svg)](https://github.com/marzliak/quick-backup-restore/actions/workflows/ci.yml)

**Hourly incremental backup for OpenClaw instances.**

Restic-powered, YAML-configured, Telegram-notified on failure. Silent on success — only pings you when something breaks.

**Platform:** Linux only (bash scripts). macOS works with Homebrew restic but is untested. Windows not supported.

---

## Quick start

```bash
git clone https://github.com/marzliak/quick-backup-restore
cd quick-backup-restore
nano config.yaml          # optional: add Telegram bot_token + chat_id for failure alerts
sudo bin/setup.sh         # installs deps, initializes repo, registers cron
```

Or, repo-only setup (no apt-get, no cron, no /usr/local/bin changes):

```bash
sudo bin/setup.sh --no-system-install
```

Done. Backups run every hour at :05.

---

## Flags

| Flag | Script | Description |
|------|--------|-------------|
| `--help` / `-h` | all scripts | Show usage and exit |
| `--skip-backup` | `setup.sh` | Skip the initial validation backup after setup |
| `--no-system-install` | `setup.sh` | Repo-only setup: creates repo dir, generates password, inits restic. Skips apt-get, cron registration, and binary install to `/usr/local/bin` |
| `--assume-yes` / `-y` | `setup.sh` | Skip dependency installation confirmation prompt (for CI/automated use) |
| `--dry-run` | `backup.sh` | Show what would be backed up without writing |
| `--keep-last N` | `prune.sh` | Override retention for this run |
| `--older-than DURATION` | `prune.sh` | Remove snapshots older than duration (e.g. `7d`, `24h`) |
| `--dry-run` | `prune.sh` | Preview cleanup without deleting |
| `--yes` / `-y` | `prune.sh` | Skip confirmation prompt |
| `--yes` / `-y` | `uninstall.sh` | Skip confirmation (system files only, preserves data) |
| `--purge` | `uninstall.sh` | Also delete repository, password file, and logs (DESTRUCTIVE) |

---

## Customize paths

```bash
sudo bin/customize.sh
```

Scans your system locally (100% offline — no API calls) and suggests:
- Extra paths worth backing up (e.g. `~/.ssh`, `~/.config`)
- Junk patterns to exclude (e.g. `node_modules`, `*.log`)

Shows suggestions and asks for confirmation before changing `config.yaml`.

---

## Status check

```bash
sudo bin/status.sh
```

Shows: version, snapshot count, last snapshot time, repo size, disk free, password file status, cron status, integrity check counter, update availability, and recent log lines.

---

## Cleanup (prune)

```bash
sudo bin/prune.sh                     # use config retention
sudo bin/prune.sh --keep-last 24      # keep only last 24
sudo bin/prune.sh --older-than 7d     # remove older than 7 days
sudo bin/prune.sh --dry-run           # preview without deleting
```

Shows before/after snapshot count and repo size. Sends Telegram notification with space reclaimed.

---

## Self-test

```bash
bash bin/test.sh
```

Validates: dependencies, config syntax, shell syntax on all scripts, and a full backup→restore→verify roundtrip in a temp directory. No root required.

---

## Uninstall

```bash
# Remove system files (preserves your backups and password)
sudo bin/uninstall.sh

# Remove everything including backups (DESTRUCTIVE — asks for confirmation)
sudo bin/uninstall.sh --purge
```

Removes: systemd timer/service, cron job, logrotate config, installed binary, lock and marker files.
Preserves (unless `--purge`): backup repository, password file, log file, source files.

---

## What gets backed up

OpenClaw's runtime context — not the full system. Your agent's brain, not the OS.

| Path | Contents |
|------|----------|
| `workspace/` | MEMORY.md, SOUL.md, USER.md, skills, memory modules |
| `sessions/` | Full agent session history (JSONL) |
| `openclaw.json` | Config, gateway settings |
| `cron/` | Scheduled jobs |

All paths configurable in `config.yaml`.

---

## Example output

After `sudo bin/setup.sh`:

```
[2026-03-04 18:17:02] [INFO ] Checking dependencies...
[2026-03-04 18:17:03] [INFO ] restic 0.17.3, yq 4.44.1 — OK
[2026-03-04 18:17:04] [INFO ] Initializing restic repository at /var/backups/time-clawshine
[2026-03-04 18:17:05] [INFO ] Repository initialized OK
[2026-03-04 18:17:06] [INFO ] Cron job registered: 5 * * * *
[2026-03-04 18:17:06] [INFO ] --- Time Clawshine setup complete ---
```

After `sudo bin/backup.sh` (first run):

```
[2026-03-04 18:18:01] [INFO ] Starting backup...
[2026-03-04 18:18:02] [INFO ]   snapshot 702a8854 saved
[2026-03-04 18:18:03] [INFO ] --- Time Clawshine finished ---
```

After `sudo bin/backup.sh` (subsequent runs — incremental):

```
[2026-03-04 19:05:01] [INFO ] Starting backup...
[2026-03-04 19:05:01] [INFO ]   using parent snapshot 702a8854
[2026-03-04 19:05:01] [INFO ]   snapshot 596e1cb3 saved
[2026-03-04 19:05:02] [INFO ] --- Time Clawshine finished ---
```

Listing snapshots:

```
$ restic -r /var/backups/time-clawshine --password-file /etc/time-clawshine.pass snapshots

ID        Time                 Host     Tags  Paths
-------------------------------------------------------
702a8854  2026-03-04 18:18:02  openclaw       /root/.openclaw/...
596e1cb3  2026-03-04 19:05:01  openclaw       /root/.openclaw/...
add992ac  2026-03-04 20:05:04  openclaw       /root/.openclaw/...
3e55adb1  2026-03-04 21:05:03  openclaw       /root/.openclaw/...
9e5c0e23  2026-03-04 22:05:03  openclaw       /root/.openclaw/...
-------------------------------------------------------
5 snapshots
```

---

## Restore

```bash
# Interactive — lists snapshots and prompts for confirmation
sudo bin/restore.sh

# Restore by time — "2 hours ago", "yesterday"
sudo bin/restore.sh "2h ago" --target /tmp/openclaw-restore
sudo bin/restore.sh yesterday --target /tmp/openclaw-restore

# Restore latest snapshot to a temp dir (safe, non-destructive)
sudo bin/restore.sh latest --target /tmp/openclaw-restore

# Restore a specific file from latest snapshot
sudo bin/restore.sh latest --file /root/.openclaw/workspace/MEMORY.md --target /tmp/openclaw-restore
```

---

## Installing as an OpenClaw workspace skill

After cloning, symlink into your workspace so it appears in the Control UI:

```bash
mkdir -p /root/.openclaw/workspace/skills
ln -s /path/to/time-clawshine /root/.openclaw/workspace/skills/time-clawshine
```

The skill will appear as `openclaw-workspace` in the Skills panel.

---

## Configuration

Everything in `config.yaml` — fully commented:

```yaml
repository:
  path: /var/backups/time-clawshine   # local path (or any restic backend)
  password_file: /etc/time-clawshine.pass  # auto-generated by setup.sh

retention:
  keep_last: 72   # 3 days at 1/hour

schedule:
  cron: "5 * * * *"   # every hour at :05

backup:
  paths:
    - /root/.openclaw/workspace
    - /root/.openclaw/agents/main/sessions
    - /root/.openclaw/openclaw.json
    - /root/.openclaw/cron
  exclude:
    - "*.bak"
    - "*.tmp"
    - ".git"

integrity:
  check_every: 24   # restic check every N backups (0 = disabled)

safety:
  min_disk_mb: 500  # abort backup if less than this free

notifications:
  telegram:
    enabled: false       # set to true to get pinged on failures
    bot_token: ""        # from @BotFather
    chat_id: ""          # from @userinfobot
    daily_digest: false  # daily summary via Telegram

updates:
  check: true   # daily version check against ClawHub
```

---

## How it fits in your backup strategy

```
Time Clawshine              ← time machine layer (this tool)
    ↓ hourly, local, 72 snapshots
Full DR backup          ← disaster recovery layer (e.g. restic to remote NAS/cloud)
    ↓ daily, off-VM
```

Time Clawshine protects against "the agent broke its own memory 2 hours ago."
Your DR backup protects against "the VM is gone."

---

## Dependencies

Auto-installed by `setup.sh`: `restic`, `yq` v4, `curl`, `jq`.

## Platform support

| Platform | Status |
|----------|--------|
| Linux    | ✅ Supported |
| macOS    | ⚠️ Untested (requires `brew install restic yq jq`) |
| Windows  | ❌ Not supported (bash scripts) |

## License

MIT — see [LICENSE.txt](LICENSE.txt)

---

## Author

**Leandro Marz** ([@marzliak](https://github.com/marzliak))

## Links

- **Repository:** [github.com/marzliak/quick-backup-restore](https://github.com/marzliak/quick-backup-restore)
- **ClawHub:** [quick-backup-restore](https://clawhub.com/skills/quick-backup-restore)
- **Issues:** [github.com/marzliak/quick-backup-restore/issues](https://github.com/marzliak/quick-backup-restore/issues)
