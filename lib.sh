#!/bin/bash
# =============================================================================
# lib.sh — shared functions for Quick Backup and Restore (time machine)
# Sourced by all bin/ scripts via: source "$TC_ROOT/lib.sh"
# =============================================================================

# --- Resolve config path -----------------------------------------------------
# lib.sh lives at project root — no ".." needed
TC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${TC_CONFIG:-$TC_ROOT/config.yaml}"

[[ -f "$CONFIG_FILE" ]] || { echo "[quick-backup-restore] ERROR: config.yaml not found at $CONFIG_FILE"; exit 1; }

# --- YAML parser (requires yq v4) -------------------------------------------
_cfg() {
    # Usage: _cfg '.repository.path'
    yq e "$1" "$CONFIG_FILE"
}

_cfg_list() {
    # Usage: _cfg_list '.backup.paths[]'  → one item per line
    yq e "$1" "$CONFIG_FILE"
}

# --- Load config into variables ----------------------------------------------
tc_load_config() {
    REPO=$(_cfg '.repository.path')
    PASS_FILE=$(_cfg '.repository.password_file')
    KEEP_LAST=$(_cfg '.retention.keep_last')
    LOG_FILE=$(_cfg '.logging.file')
    VERBOSE=$(_cfg '.logging.verbose')
    CRON_EXPR=$(_cfg '.schedule.cron')

    TG_ENABLED=$(_cfg '.notifications.telegram.enabled')
    TG_TOKEN=$(_cfg '.notifications.telegram.bot_token')
    TG_CHAT_ID=$(_cfg '.notifications.telegram.chat_id')
    TG_DAILY_DIGEST=$(_cfg '.notifications.telegram.daily_digest')

    CHECK_EVERY=$(_cfg '.integrity.check_every')
    MIN_DISK_MB=$(_cfg '.safety.min_disk_mb')
    UPDATE_CHECK=$(_cfg '.updates.check')

    # Defaults for optional fields
    [[ -z "$CHECK_EVERY"    || "$CHECK_EVERY"    == "null" ]] && CHECK_EVERY=0
    [[ -z "$MIN_DISK_MB"    || "$MIN_DISK_MB"    == "null" ]] && MIN_DISK_MB=0
    [[ -z "$TG_DAILY_DIGEST" || "$TG_DAILY_DIGEST" == "null" ]] && TG_DAILY_DIGEST=false
    [[ -z "$UPDATE_CHECK"   || "$UPDATE_CHECK"   == "null" ]] && UPDATE_CHECK=true

    # Validate critical config values
    _require_cfg() {
        local name="$1" val="$2"
        if [[ -z "$val" || "$val" == "null" ]]; then
            echo "[quick-backup-restore] ERROR: config.yaml missing required field: $name"
            exit 1
        fi
    }
    _require_cfg 'repository.path'          "$REPO"
    _require_cfg 'repository.password_file' "$PASS_FILE"
    _require_cfg 'retention.keep_last'      "$KEEP_LAST"
    _require_cfg 'logging.file'             "$LOG_FILE"

    # Build backup paths array (standard + extra)
    mapfile -t _BASE_PATHS  < <(_cfg_list '.backup.paths[]')
    mapfile -t _EXTRA_PATHS < <(_cfg_list '.backup.extra_paths[]' 2>/dev/null || true)
    BACKUP_PATHS=("${_BASE_PATHS[@]}")
    for p in "${_EXTRA_PATHS[@]}"; do
        [[ -n "$p" && "$p" != "null" ]] && BACKUP_PATHS+=("$p")
    done

    # Build exclude flags array (standard + extra)
    mapfile -t _BASE_EX  < <(_cfg_list '.backup.exclude[]')
    mapfile -t _EXTRA_EX < <(_cfg_list '.backup.extra_excludes[]' 2>/dev/null || true)
    EXCLUDES=()
    for ex in "${_BASE_EX[@]}" "${_EXTRA_EX[@]}"; do
        [[ -n "$ex" && "$ex" != "null" ]] && EXCLUDES+=("--exclude=$ex")
    done

    # Validate config types
    tc_validate_config
}

# --- Config schema validation ------------------------------------------------
tc_validate_config() {
    local errors=()

    # retention.keep_last must be a positive integer
    if ! [[ "$KEEP_LAST" =~ ^[0-9]+$ ]] || [[ "$KEEP_LAST" -le 0 ]]; then
        errors+=("retention.keep_last must be a positive integer (got: '$KEEP_LAST')")
    fi

    # safety.min_disk_mb must be a non-negative integer
    if ! [[ "$MIN_DISK_MB" =~ ^[0-9]+$ ]]; then
        errors+=("safety.min_disk_mb must be a non-negative integer (got: '$MIN_DISK_MB')")
    fi

    # integrity.check_every must be a non-negative integer
    if ! [[ "$CHECK_EVERY" =~ ^[0-9]+$ ]]; then
        errors+=("integrity.check_every must be a non-negative integer (got: '$CHECK_EVERY')")
    fi

    # schedule.cron must look like a cron expression (5 fields)
    if [[ -n "$CRON_EXPR" && "$CRON_EXPR" != "null" ]]; then
        local field_count
        field_count=$(echo "$CRON_EXPR" | awk '{print NF}')
        if [[ "$field_count" -ne 5 ]]; then
            errors+=("schedule.cron must have 5 fields (got $field_count: '$CRON_EXPR')")
        fi
    fi

    # backup.paths must have at least one entry
    if [[ ${#BACKUP_PATHS[@]} -eq 0 ]]; then
        errors+=("backup.paths must have at least one path")
    fi

    # telegram: if enabled, token and chat_id must be set
    if [[ "$TG_ENABLED" == "true" ]]; then
        [[ -z "$TG_TOKEN" || "$TG_TOKEN" == "null" ]] && \
            errors+=("notifications.telegram.bot_token is required when enabled: true")
        [[ -z "$TG_CHAT_ID" || "$TG_CHAT_ID" == "null" ]] && \
            errors+=("notifications.telegram.chat_id is required when enabled: true")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "[quick-backup-restore] CONFIG VALIDATION ERRORS:"
        for e in "${errors[@]}"; do echo "  ✗ $e"; done
        exit 1
    fi
}

# --- Logging -----------------------------------------------------------------
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    local level="${1:-INFO}"
    local msg="${2:-}"
    echo "[$(timestamp)] [$level] $msg" | tee -a "$LOG_FILE"
}

log_info()  { log "INFO " "$1"; }
log_warn()  { log "WARN " "$1"; }
log_error() { log "ERROR" "$1"; }

# --- Telegram ----------------------------------------------------------------
tg_send() {
    local msg="$1"
    [[ "$TG_ENABLED" != "true" ]]     && return 0
    [[ -z "$TG_TOKEN" ]]              && return 0
    [[ "$TG_TOKEN" == "null" ]]       && return 0
    [[ -z "$TG_CHAT_ID" ]]            && return 0
    [[ "$TG_CHAT_ID" == "null" ]]     && return 0

    curl -s -X POST \
        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$TG_CHAT_ID" \
            --arg text "$msg" \
            '{chat_id: $chat_id, text: $text, parse_mode: "Markdown"}')" \
        > /dev/null 2>&1 || true
}

tg_failure() {
    local error_msg="$1"
    local hostname; hostname=$(hostname)
    # Truncate error output to avoid leaking sensitive paths/data via Telegram
    local safe_msg
    safe_msg=$(head -c 800 <<< "$error_msg")
    [[ ${#error_msg} -gt 800 ]] && safe_msg+=$'\n[...truncated]'
    tg_send "🔴 *Time Clawshine — Backup FALHOU*
🖥 \`$hostname\`
🕐 $(timestamp)

\`\`\`
$safe_msg
\`\`\`"
}

# --- Restic wrapper ----------------------------------------------------------
restic_cmd() {
    RESTIC_PASSWORD_FILE="$PASS_FILE" restic -r "$REPO" "$@"
}

# --- Validation --------------------------------------------------------------
tc_validate_paths() {
    local missing=()
    for path in "${BACKUP_PATHS[@]}"; do
        [[ -e "$path" ]] || missing+=("$path")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Paths not found: ${missing[*]}"
        tg_failure "Paths not found:\n${missing[*]}"
        return 1
    fi
    return 0
}

tc_check_deps() {
    local missing=()
    for cmd in restic yq curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[quick-backup-restore] ERROR: Missing dependencies: ${missing[*]}"
        echo "Run: sudo bin/setup.sh"
        exit 1
    fi
}

# --- Version -----------------------------------------------------------------
tc_current_version() {
    local skill_json="$TC_ROOT/skill.json"
    if [[ -f "$skill_json" ]] && command -v jq &>/dev/null; then
        jq -r '.version' "$skill_json" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# --- Telegram digest ---------------------------------------------------------
tg_digest() {
    local snapshot_count="$1"
    local repo_size="$2"
    local disk_free="$3"
    local hostname; hostname=$(hostname)
    tg_send "📊 *Time Clawshine — Resumo diário*
🖥 \`$hostname\`
🕐 $(timestamp)

📸 Snapshots: $snapshot_count
💾 Repositório: $repo_size
💿 Disco livre: $disk_free"
}

# --- Disk space check --------------------------------------------------------
tc_check_disk() {
    local min_mb="$1"
    [[ "$min_mb" -le 0 ]] 2>/dev/null && return 0
    local repo_dir; repo_dir=$(dirname "$REPO")
    local avail_kb; avail_kb=$(df --output=avail "$repo_dir" 2>/dev/null | tail -1 | tr -d ' ')
    if [[ -z "$avail_kb" || "$avail_kb" == "Avail" ]]; then
        log_warn "Could not determine free disk space — skipping disk guard"
        return 0
    fi
    local avail_mb=$(( avail_kb / 1024 ))
    if [[ $avail_mb -lt $min_mb ]]; then
        log_error "Disk space too low: ${avail_mb}MB free < ${min_mb}MB minimum"
        tg_failure "Disco quase cheio: ${avail_mb}MB livre, mínimo configurado: ${min_mb}MB. Backup abortado."
        return 1
    fi
    return 0
}
