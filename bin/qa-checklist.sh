#!/bin/bash
# =============================================================================
# bin/qa-checklist.sh — Pre-production QA checklist for Time Clawshine v3
#
# This script is for the OpenClaw agent to run ON THE VPS before promoting
# homolog → main. It tests real system integration (requires root, real config,
# real Telegram, real cron/systemd).
#
# DOES NOT ship to production. Lives only on the homolog branch.
#
# Usage: sudo bash {baseDir}/bin/qa-checklist.sh
# =============================================================================

set -uo pipefail

TC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Colors -----------------------------------------------------------------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

PASS=0
FAIL=0
SKIP=0
TESTS=0
SECTION=""
FAILURES=()

_section() {
    SECTION="$1"
    echo ""
    echo -e "${CYAN}━━━ $1 ━━━${NC}"
}

_test() {
    TESTS=$(( TESTS + 1 ))
    echo -n "  [$TESTS] $1 ... "
}

_ok() {
    PASS=$(( PASS + 1 ))
    echo -e "${GREEN}PASS${NC}"
}

_fail() {
    FAIL=$(( FAIL + 1 ))
    FAILURES+=("[$TESTS] $SECTION: $1")
    echo -e "${RED}FAIL${NC}: $1"
}

_skip() {
    SKIP=$(( SKIP + 1 ))
    echo -e "${YELLOW}SKIP${NC}: $1"
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      Time Clawshine — Pre-Production QA Checklist        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo -e "${BOLD}Date:${NC}    $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "${BOLD}Host:${NC}    $(hostname)"
echo -e "${BOLD}User:${NC}    $(whoami)"
echo -e "${BOLD}Branch:${NC}  $(cd "$TC_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo -e "${BOLD}Commit:${NC}  $(cd "$TC_ROOT" && git log --oneline -1 2>/dev/null || echo 'unknown')"

# ============================================================================
# SECTION 1: Prerequisites
# ============================================================================
_section "1. Prerequisites"

_test "Running as root"
if [[ $EUID -eq 0 ]]; then _ok; else _fail "must run as root (sudo)"; fi

_test "config.yaml exists and parses"
if yq e '.' "$TC_ROOT/config.yaml" > /dev/null 2>&1; then _ok; else _fail "invalid YAML"; fi

_test "lib.sh loads without error"
LIB_OUT=$(bash -c "export TC_SKIP_PASS_CHECK=true; source '$TC_ROOT/lib.sh'; tc_load_config" 2>&1)
if [[ $? -eq 0 ]]; then _ok; else _fail "$LIB_OUT"; fi

_test "All dependencies installed"
MISSING=()
for cmd in restic yq curl jq bash openssl; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then _fail "missing: ${MISSING[*]}"; else _ok; fi

_test "restic version >= 0.16"
RESTIC_VER=$(restic version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
if [[ -n "$RESTIC_VER" ]]; then
    MAJOR=$(echo "$RESTIC_VER" | cut -d. -f1)
    MINOR=$(echo "$RESTIC_VER" | cut -d. -f2)
    if [[ "$MAJOR" -gt 0 ]] || [[ "$MINOR" -ge 16 ]]; then _ok; else _fail "restic $RESTIC_VER < 0.16"; fi
else
    _fail "cannot determine restic version"
fi

# ============================================================================
# SECTION 2: Password & Repository
# ============================================================================
_section "2. Password & Repository"

source "$TC_ROOT/lib.sh"
export TC_SKIP_PASS_CHECK=true
tc_load_config 2>/dev/null

PASS_FILE=$(_cfg '.repository.password_file')
REPO_PATH=$(_cfg '.repository.path')

_test "Password file exists"
if [[ -f "$PASS_FILE" ]]; then _ok; else _fail "$PASS_FILE not found"; fi

_test "Password file permissions = 600"
if [[ -f "$PASS_FILE" ]]; then
    PERMS=$(stat -c '%a' "$PASS_FILE" 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then _ok; else _fail "got $PERMS, expected 600"; fi
else
    _skip "password file missing"
fi

_test "Password file is non-empty"
if [[ -f "$PASS_FILE" ]] && [[ -s "$PASS_FILE" ]]; then _ok
elif [[ -f "$PASS_FILE" ]]; then _fail "file exists but is empty"
else _skip "password file missing"
fi

_test "Repository is initialized"
if RESTIC_PASSWORD_FILE="$PASS_FILE" restic -r "$REPO_PATH" cat config > /dev/null 2>&1; then
    _ok
else
    _fail "restic cannot read repo at $REPO_PATH"
fi

_test "Repository integrity (restic check)"
CHECK_OUT=$(RESTIC_PASSWORD_FILE="$PASS_FILE" restic -r "$REPO_PATH" check 2>&1)
if [[ $? -eq 0 ]]; then _ok; else _fail "restic check failed"; fi

# ============================================================================
# SECTION 3: Backup Cycle
# ============================================================================
_section "3. Backup Cycle"

_test "backup.sh --dry-run succeeds"
DRY_OUT=$(bash "$TC_ROOT/bin/backup.sh" --dry-run 2>&1)
if [[ $? -eq 0 ]]; then _ok; else _fail "exit $?: $DRY_OUT"; fi

_test "backup.sh creates a real snapshot"
SNAP_BEFORE=$(RESTIC_PASSWORD_FILE="$PASS_FILE" restic -r "$REPO_PATH" snapshots --json 2>/dev/null | jq length)
BACKUP_OUT=$(bash "$TC_ROOT/bin/backup.sh" 2>&1)
BACKUP_RC=$?
SNAP_AFTER=$(RESTIC_PASSWORD_FILE="$PASS_FILE" restic -r "$REPO_PATH" snapshots --json 2>/dev/null | jq length)
if [[ $BACKUP_RC -eq 0 ]] && [[ "$SNAP_AFTER" -gt "$SNAP_BEFORE" ]]; then
    _ok
else
    _fail "exit=$BACKUP_RC, snapshots before=$SNAP_BEFORE after=$SNAP_AFTER"
fi

_test "Log file exists and was written"
LOG_FILE=$(_cfg '.logging.file')
if [[ -f "$LOG_FILE" ]]; then
    # Check log was updated in the last 2 minutes
    LOG_AGE=$(( $(date +%s) - $(stat -c %Y "$LOG_FILE") ))
    if [[ $LOG_AGE -lt 120 ]]; then _ok; else _fail "log exists but last modified ${LOG_AGE}s ago"; fi
else
    _fail "$LOG_FILE not found"
fi

_test "Log contains success entry"
if grep -q "Backup complete" "$LOG_FILE" 2>/dev/null; then _ok; else _fail "no 'Backup complete' in log"; fi

# ============================================================================
# SECTION 4: Restore
# ============================================================================
_section "4. Restore"

_test "restore.sh --help exits 0"
if bash "$TC_ROOT/bin/restore.sh" --help > /dev/null 2>&1; then _ok; else _fail "non-zero exit"; fi

_test "Restore latest snapshot to temp dir"
RESTORE_TMP=$(mktemp -d)
RESTORE_OUT=$(RESTIC_PASSWORD_FILE="$PASS_FILE" restic -r "$REPO_PATH" restore latest --target "$RESTORE_TMP" 2>&1)
RESTORE_RC=$?
if [[ $RESTORE_RC -eq 0 ]] && [[ -n "$(ls -A "$RESTORE_TMP" 2>/dev/null)" ]]; then
    _ok
else
    _fail "exit=$RESTORE_RC, dir empty or failed"
fi
rm -rf "$RESTORE_TMP" 2>/dev/null

# ============================================================================
# SECTION 5: Prune & Retention
# ============================================================================
_section "5. Prune & Retention"

_test "prune.sh --dry-run succeeds"
PRUNE_OUT=$(bash "$TC_ROOT/bin/prune.sh" --dry-run 2>&1)
if [[ $? -eq 0 ]]; then _ok; else _fail "$PRUNE_OUT"; fi

KEEP_LAST=$(_cfg '.retention.keep_last')
_test "Retention configured: keep_last=$KEEP_LAST"
if [[ "$KEEP_LAST" -gt 0 ]] 2>/dev/null; then _ok; else _fail "invalid keep_last=$KEEP_LAST"; fi

# ============================================================================
# SECTION 6: Scheduler (systemd or cron)
# ============================================================================
_section "6. Scheduler"

_test "Scheduler is registered"
if systemctl is-active time-clawshine.timer &>/dev/null; then
    echo -e "${GREEN}PASS${NC} (systemd timer active)"
    PASS=$(( PASS + 1 ))
elif [[ -f /etc/cron.d/time-clawshine ]]; then
    echo -e "${GREEN}PASS${NC} (cron job found)"
    PASS=$(( PASS + 1 ))
else
    _fail "no systemd timer or /etc/cron.d/time-clawshine found"
fi

_test "Scheduler runs correct script path"
if systemctl is-active time-clawshine.timer &>/dev/null; then
    SVC_EXEC=$(systemctl cat time-clawshine.service 2>/dev/null | grep -oP 'ExecStart=\K.*' || echo "")
    if echo "$SVC_EXEC" | grep -q "bin/backup.sh"; then _ok; else _fail "ExecStart=$SVC_EXEC"; fi
elif [[ -f /etc/cron.d/time-clawshine ]]; then
    if grep -q "bin/backup.sh" /etc/cron.d/time-clawshine; then _ok; else _fail "backup.sh not in cron entry"; fi
else
    _skip "no scheduler found"
fi

# ============================================================================
# SECTION 7: Logrotate
# ============================================================================
_section "7. Logrotate"

_test "Logrotate config exists"
if [[ -f /etc/logrotate.d/time-clawshine ]]; then _ok; else _fail "/etc/logrotate.d/time-clawshine missing"; fi

_test "Logrotate config is valid"
if [[ -f /etc/logrotate.d/time-clawshine ]]; then
    if logrotate -d /etc/logrotate.d/time-clawshine > /dev/null 2>&1; then _ok; else _fail "logrotate -d failed"; fi
else
    _skip "config missing"
fi

# ============================================================================
# SECTION 8: Telegram Notifications
# ============================================================================
_section "8. Telegram Notifications"

TG_ENABLED=$(_cfg '.notifications.telegram.enabled')
TG_TOKEN=$(_cfg '.notifications.telegram.bot_token')
TG_CHAT=$(_cfg '.notifications.telegram.chat_id')

_test "Telegram config present"
if [[ "$TG_ENABLED" == "true" ]]; then
    if [[ -n "$TG_TOKEN" ]] && [[ -n "$TG_CHAT" ]] && [[ "$TG_TOKEN" != "null" ]] && [[ "$TG_CHAT" != "null" ]]; then
        _ok
    else
        _fail "enabled=true but token or chat_id empty"
    fi
else
    _skip "Telegram disabled in config"
fi

_test "Telegram bot can send a message"
if [[ "$TG_ENABLED" == "true" ]] && [[ -n "$TG_TOKEN" ]] && [[ "$TG_TOKEN" != "null" ]]; then
    TG_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT" \
        -d text="🧪 QA checklist: Telegram test from $(hostname) at $(date '+%H:%M')" \
        -d parse_mode=HTML 2>/dev/null)
    if [[ "$TG_RESP" == "200" ]]; then _ok; else _fail "HTTP $TG_RESP"; fi
else
    _skip "Telegram disabled"
fi

# ============================================================================
# SECTION 9: Disk Safety
# ============================================================================
_section "9. Disk Safety"

MIN_DISK=$(_cfg '.safety.min_disk_mb')
_test "Disk guard configured: min_disk_mb=$MIN_DISK"
if [[ "$MIN_DISK" -ge 0 ]] 2>/dev/null; then _ok; else _fail "invalid value"; fi

REPO_DISK_FREE=$(df -m "$REPO_PATH" 2>/dev/null | awk 'NR==2{print $4}')
_test "Repo volume has enough free space (${REPO_DISK_FREE:-?} MB free, need $MIN_DISK MB)"
if [[ -n "$REPO_DISK_FREE" ]] && [[ "$REPO_DISK_FREE" -ge "$MIN_DISK" ]]; then
    _ok
else
    _fail "only ${REPO_DISK_FREE:-0} MB free"
fi

# ============================================================================
# SECTION 10: Status Dashboard
# ============================================================================
_section "10. Status Dashboard"

_test "status.sh runs without error"
STATUS_OUT=$(bash "$TC_ROOT/bin/status.sh" 2>&1)
if [[ $? -eq 0 ]]; then _ok; else _fail "exit non-zero"; fi

_test "status.sh shows snapshot count"
if echo "$STATUS_OUT" | grep -qiE "snapshot|backup"; then _ok; else _fail "no snapshot info in output"; fi

# ============================================================================
# SECTION 11: Uninstall (dry check only)
# ============================================================================
_section "11. Uninstall (syntax only — NOT executed)"

_test "uninstall.sh --help exits 0"
if bash "$TC_ROOT/bin/uninstall.sh" --help > /dev/null 2>&1; then _ok; else _fail "non-zero exit"; fi

_test "uninstall.sh passes syntax check"
if bash -n "$TC_ROOT/bin/uninstall.sh" 2>/dev/null; then _ok; else _fail "bash -n failed"; fi

# ============================================================================
# SECTION 12: v2 Migration (check only)
# ============================================================================
_section "12. v2 Legacy Artifacts"

_test "No v2 cron leftover"
if [[ -f /etc/cron.d/quick-backup-restore ]]; then _fail "v2 cron still present"; else _ok; fi

_test "No v2 logrotate leftover"
if [[ -f /etc/logrotate.d/quick-backup-restore ]]; then _fail "v2 logrotate still present"; else _ok; fi

_test "No v2 lock leftover"
if [[ -f /var/lock/quick-backup-restore.lock ]]; then _fail "v2 lock still present"; else _ok; fi

_test "No v2 marker files leftover"
V2_MARKERS=$(ls /var/tmp/quick-backup-restore-* 2>/dev/null | head -3)
if [[ -n "$V2_MARKERS" ]]; then _fail "found: $V2_MARKERS"; else _ok; fi

# ============================================================================
# SECTION 13: Security
# ============================================================================
_section "13. Security"

_test "No secrets in config.yaml committed to git"
if cd "$TC_ROOT" && git log --all -p -- config.yaml 2>/dev/null | grep -qiE 'bot_token:\s*"[^"]+[0-9]{5,}'; then
    _fail "Telegram token appears in git history"
else
    _ok
fi

_test "Password file is outside repository"
if [[ "$PASS_FILE" == "$TC_ROOT"* ]]; then
    _fail "password file is inside the plugin directory — risk of committing"
else
    _ok
fi

_test "Binary symlink exists"
if [[ -x /usr/local/bin/quick-backup-restore ]]; then _ok; else _fail "/usr/local/bin/quick-backup-restore missing or not executable"; fi

# ============================================================================
# SECTION 14: All --help Flags
# ============================================================================
_section "14. All Scripts --help"

for script in backup.sh setup.sh restore.sh status.sh customize.sh prune.sh test.sh uninstall.sh; do
    _test "--help: $script"
    HELP_OUT=$(bash "$TC_ROOT/bin/$script" --help 2>&1)
    if [[ $? -eq 0 ]] && [[ -n "$HELP_OUT" ]]; then _ok; else _fail "exit non-zero or empty output"; fi
done

# ============================================================================
# REPORT
# ============================================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo ""
TOTAL=$(( PASS + FAIL + SKIP ))
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}  |  ${YELLOW}SKIP: $SKIP${NC}  |  TOTAL: $TOTAL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}  ✗ NOT ready for production.${NC} Fix these:"
    echo ""
    for f in "${FAILURES[@]}"; do
        echo -e "    ${RED}•${NC} $f"
    done
    echo ""
    echo "══════════════════════════════════════════════════════════"
    exit 1
else
    echo -e "${GREEN}  ✓ All checks passed. Ready for production.${NC}"
    echo ""
    echo "══════════════════════════════════════════════════════════"
    exit 0
fi
