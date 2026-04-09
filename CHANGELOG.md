# Changelog

All notable changes to Quick Backup and Restore (time machine) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.2.0] — 2026-04-09

### Added
- `bin/status.sh`: health check showing version, snapshots, repo size, disk space, cron, password file warning, integrity counter, update check, and last log lines
- Disk space guard (`safety.min_disk_mb`): aborts backup and sends Telegram alert if free disk is below threshold
- Periodic integrity check (`integrity.check_every`): runs `restic check` every N backups (default 24 = daily with hourly cron)
- Daily digest via Telegram (`notifications.telegram.daily_digest`): summary with snapshot count, repo size, and disk free — sent on first backup after midnight
- Update version check (`updates.check`): daily non-blocking check against ClawHub API, logs a warning if a newer version is available
- Logrotate configuration: `setup.sh` now creates `/etc/logrotate.d/quick-backup-restore` for weekly log rotation (4 weeks, compressed)

### Fixed
- `config.yaml` comment on line 59 claimed logrotate was already set up — now it actually is

---

## [1.1.1] — 2026-04-09

### Fixed
- SKILL.md metadata: declared full dependency list (`bash`, `openssl`, `curl`, `jq` + auto_install `restic`, `yq`) — was previously only `bash` and `openssl`

---

## [1.1.0] — 2026-04-09

### Changed
- `bin/customize.sh`: replaced `openclaw agent ask` with pure bash analysis — no data leaves the machine
- `bin/setup.sh`: added `--no-system-install` flag for repo-only setup without root modifications
- `bin/setup.sh`: added dependency install confirmation prompt (override with `--assume-yes` / `-y`)

### Removed
- Deleted `prompts/whitelist.txt` and `prompts/blacklist.txt` (no longer needed)

### Security
- Eliminates workspace listing exfiltration risk flagged by ClawHub security scan
- Users can now set up backup repo without modifying system files

---

## [1.0.0] — 2026-03-04

Initial release.

### Added

**Core backup engine**
- `bin/backup.sh` — hourly restic backup; silent on success; Telegram notification on failure; validates paths before running
- `bin/restore.sh` — interactive restore with mandatory dry-run preview; `--file` and `--target` flags for surgical restores
- `bin/setup.sh` — self-installing setup: installs `restic`, `yq v4`, `curl`, `jq`; initializes AES-256 encrypted repo; registers cron from config
- `lib.sh` — shared layer for all scripts: YAML parsing, structured logging, Telegram wrapper, restic wrapper, path/dep validation

**AI-assisted customization**
- `bin/customize.sh` — analyzes actual workspace, runs AI prompts via the OpenClaw agent, shows whitelist/blacklist suggestions, applies to `config.yaml` only after explicit user confirmation; saves `config.yaml.bak` before any change
- `prompts/whitelist.txt` — template asking the agent to identify extra paths worth backing up
- `prompts/blacklist.txt` — template asking the agent to identify patterns that should be excluded

**Configuration**
- `config.yaml` as single source of truth — zero hardcoded values in any script
- Full standard OpenClaw path coverage by default: `workspace/`, `sessions/`, `openclaw.json`, `cron/`, `credentials/`
- `backup.extra_paths` and `backup.extra_excludes` as clean extension points for custom additions

**OpenClaw skill**
- `SKILL.md` with ClaWHub-compatible frontmatter (single-line metadata, correct `metadata.openclaw` namespace)
- Agent instruction body covering: setup, manual backup, status check, restore, integrity check, config changes, and customization

**Other**
- `CHANGELOG.md` in Keep a Changelog format
- `.gitignore` pre-configured: excludes `.pass`, `.env`, `secrets.*`, `.bak`, backup directories
- 72-snapshot retention (3 days at 1/hour), configurable via `retention.keep_last`

---

[1.0.0]: https://github.com/marzliak/quick-backup-restore/releases/tag/v1.0.0
