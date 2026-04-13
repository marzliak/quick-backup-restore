# Changelog

All notable changes to Time Clawshine are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [3.0.0] — 2026-04-12

### Added
- `bin/uninstall.sh`: clean removal of all system artifacts with `--yes` and `--purge` flags. Sends Telegram notification. Preserves backup data by default
- `--help` / `-h` flag on all scripts (exits before config load so it works without a valid config)
- GitHub Actions CI: runs `shellcheck` + test suite on `ubuntu-22.04` and `ubuntu-24.04` with yq checksum verification
- v2→v3 migration engine `_migrate_v2()` in `setup.sh`: auto-detects legacy v2.x system files (cron, logrotate, lock, markers), prompts to migrate, cleans old and renames markers
- `SETUP_GUIDE.md`: Step 0 (upgrade from v2) and Step 9 (uninstall) sections
- Password file existence check in `tc_load_config` — clear error instead of cryptic restic failure
- Signal trap (`SIGTERM`/`SIGINT`) in `backup.sh` — sends Telegram on unexpected termination
- `openssl` added to `tc_check_deps` (was required by setup but not validated)
- ARM64 and ARMv7 support for yq download in `setup.sh` (auto-detects `uname -m`)

### Changed
- **BREAKING**: System file paths renamed from `quick-backup-restore` to `time-clawshine`:
  - `/etc/cron.d/quick-backup-restore` → `/etc/cron.d/time-clawshine`
  - `/etc/logrotate.d/quick-backup-restore` → `/etc/logrotate.d/time-clawshine`
  - `/var/lock/quick-backup-restore.lock` → `/var/lock/time-clawshine.lock`
  - `/var/tmp/quick-backup-restore-*` → `/var/tmp/time-clawshine-*`
- **BREAKING**: Default config paths now use `time-clawshine` name (new installs only; existing configs are preserved)
- `backup.sh`: split `forget` (every backup) from `prune` (daily) — avoids hourly I/O storms on large repos
- `restore.sh`: now checks `restic restore` exit code — no longer shows "✓" on failure
- `customize.sh`: added missing `set -e` — prevents silent config corruption on errors
- `status.sh`: detects systemd timer (not just cron) and caches `restic snapshots --json` (single call instead of two)
- `backup.sh`: ensures log directory exists (`mkdir -p`) before first write
- `setup.sh`: fixed password warning box alignment, yq checksum now uses `checksums-bsd` format
- `setup.sh`: binary now installs as `/usr/local/bin/time-clawshine` with backward-compat symlink
- `prune.sh`: fixed SIGPIPE (exit 141) when capturing large restic output with `set -euo pipefail` — now uses temp files
- All UI headers, log messages, error prefixes, and Telegram notifications now show "Time Clawshine"
- `SKILL.md` technical reference uses config-based paths instead of hardcoded defaults
- `README.md` updated with CI badge, uninstall section, expanded flags table
- Binary symlink `/usr/local/bin/quick-backup-restore` → `time-clawshine` preserved for backward compatibility
- Test suite expanded to 25 tests (--help checks, uninstall.sh syntax, prune dry-run, permissions)

### Removed
- `CHANGES-PLAN.md` and `quick-backup-restore-changes.md` (stale planning files)

---

## [2.0.2] — 2026-04-09

### Fixed
- Telegram notifications (`tg_failure`, `tg_digest`) now show "Time Clawshine" instead of legacy "Quick Backup and Restore" name

---

## [2.0.1] — 2026-04-09

### Fixed
- `setup.sh`: yq checksum verification failed (404) — yq publishes a bulk `checksums` file, not individual `.sha256` per binary. Now downloads the correct file and greps for the matching hash
- `setup.sh`: scripts missing execute permission on some platforms — added `chmod +x` for all `bin/*.sh` and `lib.sh` at startup
- `test.sh`: roundtrip hash comparison used absolute paths causing false mismatch — switched to relative paths via `cd`

---

## [2.0.0] — 2026-04-09

### Added
- `bin/prune.sh`: manual repository cleanup with `--keep-last`, `--older-than`, `--dry-run`, `--yes` flags. Shows before/after size and sends Telegram notification
- `bin/test.sh`: self-test suite — validates deps, config, shell syntax on all scripts, and runs a full backup→restore→verify roundtrip in a temp directory
- `SETUP_GUIDE.md`: interactive setup guide for the OpenClaw agent — walks the user through Telegram, frequency, retention, paths, disk safety, and repo location before running setup.sh
- Config validation (`tc_validate_config`): validates types, ranges, cron syntax, required Telegram fields, and backup paths on every config load
- `backup.sh --dry-run`: validates backup without writing (uses `restic backup --dry-run`)
- `restore.sh` time-based restore: `"2h ago"`, `"1d ago"`, `"yesterday"` — resolves to closest snapshot automatically
- `restore.sh` Telegram notification on successful restore
- Systemd timer support: `setup.sh` auto-detects systemd and prefers `time-clawshine.timer` over cron. Falls back to cron if systemd is unavailable

### Changed
- SKILL.md: complete hero copy rewrite with marketing-grade intro, problem/solution table, and feature highlights
- SKILL.md: added sections for prune, dry-run, test, guided setup, and time-based restore
- README.md: added prune, self-test, dry-run, and time-based restore documentation
- Title unified to "Time Clawshine" across all files

---

## [1.3.0] — 2026-04-09

### Changed
- SKILL.md: complete rewrite of hero copy — marketing-grade intro with problem/solution table, feature highlights, and technical reference below
- Title unified to "Time Clawshine" across all docs

---

## [1.2.4] — 2026-04-09

### Changed
- SKILL.md description rewritten to lead with the name and purpose (visible as summary on ClawHub)

---

## [1.2.3] — 2026-04-09

### Changed
- Description: emphasize restic's incremental deduplication (near-instant backups, tiny storage)

---

## [1.2.2] — 2026-04-09

### Changed
- Display name unified to "Time Clawshine" across skill.json and ClawHub
- Description rewritten to explain the name and purpose

---

## [1.2.1] — 2026-04-09

### Fixed
- SKILL.md: removed false claim that `credentials/` are backed up by default — only paths listed in `config.yaml` are covered

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
