#!/bin/bash
# =============================================================================
# bin/backup.sh — Time Clawshine backup engine
# Called by cron/systemd every hour — silent on success, Telegram on failure
# =============================================================================

set -euo pipefail

TC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Parse flags (before sourcing lib.sh so --help works without config) -----
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: bin/backup.sh [options]"
            echo ""
            echo "Options:"
            echo "  --dry-run     Show what would be backed up without writing"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Normally called automatically by cron/systemd. Can be run manually."
            exit 0
            ;;
    esac
done

source "$TC_ROOT/lib.sh"

tc_check_deps
tc_load_config

# Ensure log directory and file exist
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || { echo "ERROR: Cannot write to $LOG_FILE"; exit 1; }

# --- Signal trap — notify on unexpected termination ------------------------
trap 'log_error "Backup interrupted by signal"; tg_failure "Backup interrupted by signal on $(hostname)"; exit 1' SIGTERM SIGINT

# --- Concurrency lock — skip if another backup is already running -----------
exec 200>/var/lock/time-clawshine.lock
chmod 600 /var/lock/time-clawshine.lock 2>/dev/null || true
flock -n 200 || { log_warn "Another backup is already running — skipping"; exit 0; }

log_info "--- Time Clawshine started ---"

# --- Disk space guard -------------------------------------------------------
tc_check_disk "$MIN_DISK_MB" || exit 1

# --- Validate backup paths --------------------------------------------------
tc_validate_paths || exit 1

# --- Run backup -------------------------------------------------------------
RESTIC_ARGS=(backup "${BACKUP_PATHS[@]}" "${EXCLUDES[@]}")
[[ "$VERBOSE" == "true" ]] && RESTIC_ARGS+=(--verbose)
[[ "$DRY_RUN" == "true" ]] && RESTIC_ARGS+=(--dry-run)

BACKUP_OUTPUT=$(restic_cmd "${RESTIC_ARGS[@]}" 2>&1)
BACKUP_EXIT=$?

if [[ $BACKUP_EXIT -ne 0 ]]; then
    log_error "restic backup failed (exit $BACKUP_EXIT)"
    log_error "$BACKUP_OUTPUT"
    tg_failure "restic backup failed (exit $BACKUP_EXIT):\n\n$BACKUP_OUTPUT"
    exit 1
fi

# Log summary lines only (not full verbose output unless configured)
if [[ "$VERBOSE" == "true" ]]; then
    while IFS= read -r line; do log_info "  $line"; done <<< "$BACKUP_OUTPUT"
else
    grep -E "(snapshot|Added to the repo|processed)" <<< "$BACKUP_OUTPUT" \
        | while IFS= read -r line; do log_info "  $line"; done || true
fi

log_info "Backup OK"

# --- In dry-run mode, stop here ---------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run complete — no changes made"
    log_info "--- Time Clawshine finished (dry-run) ---"
    exit 0
fi

# --- Apply retention policy -------------------------------------------------
log_info "Applying retention policy (keep-last $KEEP_LAST)..."

FORGET_OUTPUT=$(restic_cmd forget --keep-last "$KEEP_LAST" 2>&1)
FORGET_EXIT=$?

if [[ $FORGET_EXIT -ne 0 ]]; then
    log_error "restic forget failed (exit $FORGET_EXIT)"
    log_error "$FORGET_OUTPUT"
    tg_failure "restic forget failed (exit $FORGET_EXIT):\n\n$FORGET_OUTPUT"
    exit 1
fi

log_info "Retention OK"

# --- Periodic prune (heavy I/O — run once per day, not every backup) --------
PRUNE_MARKER="/var/tmp/time-clawshine-prune-date"
PRUNE_TODAY=$(date '+%Y-%m-%d')
LAST_PRUNE=""
[[ -f "$PRUNE_MARKER" ]] && LAST_PRUNE=$(cat "$PRUNE_MARKER" 2>/dev/null || true)

if [[ "$LAST_PRUNE" != "$PRUNE_TODAY" ]]; then
    log_info "Running daily prune (data repack)..."
    PRUNE_OUTPUT=$(restic_cmd prune 2>&1)
    PRUNE_EXIT=$?
    if [[ $PRUNE_EXIT -ne 0 ]]; then
        log_error "restic prune failed (exit $PRUNE_EXIT)"
        log_error "$PRUNE_OUTPUT"
        tg_failure "restic prune failed (exit $PRUNE_EXIT):\n\n$PRUNE_OUTPUT"
    else
        log_info "Prune OK"
    fi
    echo "$PRUNE_TODAY" > "$PRUNE_MARKER"
fi

# --- Integrity check (periodic restic check) --------------------------------
if [[ "$CHECK_EVERY" -gt 0 ]]; then
    COUNTER_FILE="/var/tmp/time-clawshine-check-counter"
    COUNTER=0
    [[ -f "$COUNTER_FILE" ]] && COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    COUNTER=$(( COUNTER + 1 ))

    if [[ $COUNTER -ge $CHECK_EVERY ]]; then
        log_info "Running periodic integrity check (every $CHECK_EVERY backups)..."
        CHECK_OUTPUT=$(restic_cmd check 2>&1)
        CHECK_EXIT=$?
        if [[ $CHECK_EXIT -ne 0 ]]; then
            log_error "restic check failed (exit $CHECK_EXIT)"
            log_error "$CHECK_OUTPUT"
            tg_failure "restic check failed (exit $CHECK_EXIT):\n\n$CHECK_OUTPUT"
        else
            log_info "Integrity check OK"
        fi
        COUNTER=0
    fi

    echo "$COUNTER" > "$COUNTER_FILE"
fi

# --- Daily digest (first backup after midnight) -----------------------------
if [[ "$TG_DAILY_DIGEST" == "true" && "$TG_ENABLED" == "true" ]]; then
    DIGEST_MARKER="/var/tmp/time-clawshine-digest-date"
    TODAY=$(date '+%Y-%m-%d')
    LAST_DIGEST=""
    [[ -f "$DIGEST_MARKER" ]] && LAST_DIGEST=$(cat "$DIGEST_MARKER" 2>/dev/null || true)

    if [[ "$LAST_DIGEST" != "$TODAY" ]]; then
        SNAP_COUNT=$(restic_cmd snapshots --json 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
        REPO_SIZE="?"
        [[ -d "$REPO" ]] && REPO_SIZE=$(du -sh "$REPO" 2>/dev/null | awk '{print $1}' || echo "?")
        REPO_DIR=$(dirname "$REPO")
        DISK_FREE=$(df -h "$REPO_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "?")
        tg_digest "$SNAP_COUNT" "$REPO_SIZE" "$DISK_FREE"
        echo "$TODAY" > "$DIGEST_MARKER"
        log_info "Daily digest sent"
    fi
fi

# --- Update version check (once per day, non-blocking) ----------------------
if [[ "$UPDATE_CHECK" == "true" ]]; then
    UPDATE_MARKER="/var/tmp/time-clawshine-update-date"
    TODAY=${TODAY:-$(date '+%Y-%m-%d')}
    LAST_UPDATE_CHECK=""
    [[ -f "$UPDATE_MARKER" ]] && LAST_UPDATE_CHECK=$(cat "$UPDATE_MARKER" 2>/dev/null || true)

    if [[ "$LAST_UPDATE_CHECK" != "$TODAY" ]]; then
        CURRENT_VER=$(tc_current_version)
        CLAWHUB_API="https://clawhub.com/api/v1/skills/quick-backup-restore"
        REMOTE_VER=$(curl -s --max-time 5 "$CLAWHUB_API" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)
        if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VER" ]]; then
            log_warn "New version available: v$REMOTE_VER (current: v$CURRENT_VER). Run: clawhub update quick-backup-restore"
        fi
        echo "$TODAY" > "$UPDATE_MARKER"
    fi
fi

log_info "--- Time Clawshine finished ---"
