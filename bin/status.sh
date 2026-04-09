#!/bin/bash
# =============================================================================
# bin/status.sh — Quick Backup and Restore (time machine) health check
# Run: sudo bin/status.sh
# =============================================================================

set -euo pipefail

TC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$TC_ROOT/lib.sh"

tc_check_deps
tc_load_config

VERSION=$(tc_current_version)

echo "╔═════════════════════════════════════════════════╗"
echo "║  Quick Backup and Restore — Status               ║"
echo "╚═════════════════════════════════════════════════╝"
echo ""

# --- Version ----------------------------------------------------------------
echo "  Version         : $VERSION"

# --- Repository info --------------------------------------------------------
echo "  Repository      : $REPO"

if restic_cmd snapshots &>/dev/null; then
    SNAP_COUNT=$(restic_cmd snapshots --json 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
    LAST_SNAP=$(restic_cmd snapshots --json 2>/dev/null | jq -r '.[-1].time // "none"' 2>/dev/null | cut -d'.' -f1 | tr 'T' ' ')
    echo "  Snapshots       : $SNAP_COUNT"
    echo "  Last snapshot   : $LAST_SNAP"

    # Repo size (stats can be slow on large repos, so we use du as fallback)
    if [[ -d "$REPO" ]]; then
        REPO_SIZE=$(du -sh "$REPO" 2>/dev/null | awk '{print $1}')
        echo "  Repo size       : $REPO_SIZE"
    fi
else
    echo "  Snapshots       : (repository not initialized)"
fi

# --- Disk space -------------------------------------------------------------
if [[ -d "$REPO" ]]; then
    REPO_DIR=$(dirname "$REPO")
    DISK_FREE=$(df -h "$REPO_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    DISK_USED_PCT=$(df -h "$REPO_DIR" 2>/dev/null | awk 'NR==2{print $5}')
    echo "  Disk free       : $DISK_FREE (${DISK_USED_PCT} used)"
    if [[ "$MIN_DISK_MB" -gt 0 ]] 2>/dev/null; then
        echo "  Min disk guard  : ${MIN_DISK_MB}MB"
    fi
fi

# --- Password file ----------------------------------------------------------
echo ""
if [[ -f "$PASS_FILE" ]]; then
    PASS_PERMS=$(stat -c '%a' "$PASS_FILE" 2>/dev/null || stat -f '%Lp' "$PASS_FILE" 2>/dev/null || echo "?")
    echo "  Password file   : $PASS_FILE (mode $PASS_PERMS)"
    echo "  ⚠  Back this up separately — without it, no restore is possible."
else
    echo "  Password file   : $PASS_FILE (NOT FOUND — CRITICAL)"
fi

# --- Cron -------------------------------------------------------------------
echo ""
CRON_FILE="/etc/cron.d/quick-backup-restore"
if [[ -f "$CRON_FILE" ]]; then
    echo "  Cron job        : $CRON_FILE"
    echo "  Schedule        : $CRON_EXPR"
else
    echo "  Cron job        : not installed (run setup.sh to register)"
fi

# --- Integrity check --------------------------------------------------------
if [[ "$CHECK_EVERY" -gt 0 ]] 2>/dev/null; then
    COUNTER_FILE="/var/tmp/quick-backup-restore-check-counter"
    if [[ -f "$COUNTER_FILE" ]]; then
        COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "?")
        echo "  Integrity check : every $CHECK_EVERY backups (counter: $COUNTER)"
    else
        echo "  Integrity check : every $CHECK_EVERY backups (counter not started)"
    fi
else
    echo "  Integrity check : disabled"
fi

# --- Update check -----------------------------------------------------------
if [[ "$UPDATE_CHECK" == "true" ]]; then
    CLAWHUB_API="https://clawhub.com/api/v1/skills/quick-backup-restore"
    REMOTE_VERSION=$(curl -s --max-time 5 "$CLAWHUB_API" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)
    if [[ -n "$REMOTE_VERSION" && "$REMOTE_VERSION" != "$VERSION" ]]; then
        echo "  Update          : v$REMOTE_VERSION available (current: v$VERSION)"
        echo "                    Run: clawhub update quick-backup-restore"
    elif [[ -n "$REMOTE_VERSION" ]]; then
        echo "  Update          : up to date (v$VERSION)"
    else
        echo "  Update          : could not reach ClawHub"
    fi
else
    echo "  Update check    : disabled"
fi

# --- Recent log --------------------------------------------------------------
echo ""
echo "  --- Last 10 log lines ---"
if [[ -f "$LOG_FILE" ]]; then
    tail -10 "$LOG_FILE" | sed 's/^/  /'
else
    echo "  (no log file found)"
fi

echo ""
