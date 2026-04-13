#!/bin/bash
# =============================================================================
# bin/setup.sh — Time Clawshine initial setup
# Run once as root: sudo bin/setup.sh
# =============================================================================

set -euo pipefail

TC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$TC_ROOT/lib.sh"

# Flags
SKIP_BACKUP=false
NO_SYSTEM=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --skip-backup)       SKIP_BACKUP=true ;;
        --no-system-install) NO_SYSTEM=true ;;
        --assume-yes|-y)     ASSUME_YES=true ;;
        --help|-h)
            echo "Usage: sudo bin/setup.sh [options]"
            echo ""
            echo "Options:"
            echo "  --skip-backup          Skip initial validation backup after setup"
            echo "  --no-system-install    Repo-only setup: no apt-get, no cron/systemd, no /usr/local/bin"
            echo "  --assume-yes, -y       Skip confirmation prompts (for CI/automated use)"
            echo "  --help, -h             Show this help"
            exit 0
            ;;
    esac
done

# Must run as root
[[ $EUID -eq 0 ]] || { echo "ERROR: Run as root (sudo bin/setup.sh)"; exit 1; }

echo "╔══════════════════════════════════════╗"
echo "║    Time Clawshine — Setup            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# --- Ensure all scripts are executable (git may strip +x on some platforms) --
chmod +x "$TC_ROOT/bin/"*.sh "$TC_ROOT/lib.sh" 2>/dev/null || true

# --- Detect and migrate v2.x artifacts --------------------------------------
_migrate_v2() {
    local v2_artifacts=()
    [[ -f "/etc/cron.d/quick-backup-restore" ]]        && v2_artifacts+=("/etc/cron.d/quick-backup-restore")
    [[ -f "/etc/logrotate.d/quick-backup-restore" ]]    && v2_artifacts+=("/etc/logrotate.d/quick-backup-restore")
    [[ -f "/var/lock/quick-backup-restore.lock" ]]      && v2_artifacts+=("/var/lock/quick-backup-restore.lock")
    for f in /var/tmp/quick-backup-restore-*; do
        [[ -e "$f" ]] && v2_artifacts+=("$f")
    done

    [[ ${#v2_artifacts[@]} -eq 0 ]] && return 0

    echo ""
    echo "==> Detected v2.x installation artifacts:"
    for a in "${v2_artifacts[@]}"; do echo "    - $a"; done
    echo ""
    echo "    These will be cleaned up. Your repository, password, and snapshots are preserved."

    if [[ "$ASSUME_YES" != "true" ]]; then
        read -rp "    Proceed with migration? [Y/n]: " CONFIRM_MIG
        [[ "$CONFIRM_MIG" =~ ^[Nn]$ ]] && { echo "    Skipping migration."; return 0; }
    fi

    for a in "${v2_artifacts[@]}"; do
        rm -f "$a" && echo "    Removed: $a"
    done

    # Rename v2 marker files to v3 equivalents
    for old_marker in /var/tmp/quick-backup-restore-check-counter \
                      /var/tmp/quick-backup-restore-digest-date \
                      /var/tmp/quick-backup-restore-update-date; do
        if [[ -f "$old_marker" ]]; then
            new_marker="${old_marker//quick-backup-restore/time-clawshine}"
            mv "$old_marker" "$new_marker" 2>/dev/null && echo "    Renamed: $old_marker → $new_marker"
        fi
    done

    echo "    ✓ v2 migration complete"
    echo ""
}

_migrate_v2

# --- Install dependencies ---------------------------------------------------
if [[ "$NO_SYSTEM" == "true" ]]; then
    echo "==> --no-system-install: skipping dependency installation"
    tc_check_deps || { echo "ERROR: Dependencies missing. Install manually or run without --no-system-install"; exit 1; }
else
    echo "==> Checking dependencies..."

    # Build list of missing packages
    MISSING_PKGS=()
    for pkg in restic curl jq; do
        command -v "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
    done
    if ! command -v yq &>/dev/null; then
        MISSING_PKGS+=("yq (from GitHub)")
    fi

    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
        echo "==> The following dependencies will be installed:"
        for p in "${MISSING_PKGS[@]}"; do echo "    - $p"; done
        if [[ "$ASSUME_YES" != "true" ]]; then
            read -rp "Proceed? [y/N]: " CONFIRM_DEPS
            [[ "$CONFIRM_DEPS" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
        fi
    else
        echo "    All dependencies already installed — OK"
    fi

    install_pkg() {
        local pkg="$1"
        if ! command -v "$pkg" &>/dev/null; then
            echo "    Installing $pkg..."
            apt-get install -qq -y "$pkg"
        else
            echo "    $pkg already installed — OK"
        fi
    }

    apt-get update -qq

    install_pkg restic
    install_pkg curl
    install_pkg jq

    # yq — install from GitHub if not present (apt version often outdated)
    if ! command -v yq &>/dev/null; then
        echo "    Installing yq..."
        YQ_VERSION="v4.44.1"
        YQ_BIN="/usr/local/bin/yq"
        case "$(uname -m)" in
            x86_64)  YQ_BINARY="yq_linux_amd64" ;;
            aarch64) YQ_BINARY="yq_linux_arm64" ;;
            armv7l)  YQ_BINARY="yq_linux_arm" ;;
            *)       echo "    ERROR: Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac
        YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"
        YQ_BSD_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums-bsd"

        # 1. Download checksum FIRST (fail early if unavailable)
        EXPECTED_SHA=$(curl -sL "$YQ_BSD_URL" | grep "^SHA256 (${YQ_BINARY})" | awk -F'= ' '{print $2}')
        if [[ -z "$EXPECTED_SHA" ]]; then
            echo "    WARN: Could not fetch yq checksum — skipping verification"
        fi

        # 2. Download binary
        curl -sL "$YQ_URL" -o "$YQ_BIN"

        # 3. Verify checksum
        if [[ -n "$EXPECTED_SHA" ]]; then
            ACTUAL_SHA=$(sha256sum "$YQ_BIN" | awk '{print $1}')
            if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
                rm -f "$YQ_BIN"
                echo "    ERROR: yq checksum mismatch! Expected $EXPECTED_SHA, got $ACTUAL_SHA"
                echo "    Binary removed. Possible supply chain compromise — investigate before retrying."
                exit 1
            fi
        fi
        chmod +x "$YQ_BIN"
        echo "    yq $YQ_VERSION installed (checksum verified) — OK"
    else
        echo "    yq already installed — OK"
    fi
fi

# --- Load config (after deps are ready) ------------------------------------
export TC_SKIP_PASS_CHECK=true  # password file may not exist yet during setup
tc_load_config

# --- Create repository directory -------------------------------------------
echo ""
echo "==> Creating repository directory: $REPO"
mkdir -p "$REPO"
chmod 700 "$REPO"

# --- Generate password (skip if already exists) ----------------------------
echo ""
if [[ -f "$PASS_FILE" ]]; then
    echo "==> Password file already exists: $PASS_FILE — skipping generation"
else
    echo "==> Generating restic encryption password..."
    mkdir -p "$(dirname "$PASS_FILE")"
    # Safety: refuse to overwrite if file appeared between check and write
    if [[ -f "$PASS_FILE" ]]; then
        echo "    WARN: Password file appeared unexpectedly at $PASS_FILE — not overwriting"
    else
        ( set -C; openssl rand -base64 48 > "$PASS_FILE" ) 2>/dev/null \
            || { echo "ERROR: Could not write password to $PASS_FILE"; exit 1; }
        chmod 600 "$PASS_FILE"
    fi
    echo ""
    echo "    ┌──────────────────────────────────────────────────────────┐"
    echo "    │  Password saved to: $PASS_FILE"
    echo "    │                                                          │"
    echo "    │  *** BACK THIS UP — without it, no restore is possible, │"
    echo "    │  even if the repo is intact ***                         │"
    echo "    └──────────────────────────────────────────────────────────┘"
    echo ""
    echo "    To view the password later: sudo cat $PASS_FILE"
fi

# --- Initialize restic repo ------------------------------------------------
echo ""
echo "==> Initializing restic repository..."
if restic_cmd snapshots &>/dev/null; then
    echo "    Repository already initialized — OK"
else
    restic_cmd init
    echo "    Repository initialized — OK"
fi

# --- Install backup script to bin ------------------------------------------
if [[ "$NO_SYSTEM" == "true" ]]; then
    echo ""
    echo "==> --no-system-install: skipping binary install, cron, and config permissions"
    CRON_FILE="N/A (--no-system-install)"
else
    echo ""
    echo "==> Installing backup script to /usr/local/bin/time-clawshine..."
    cp "$TC_ROOT/bin/backup.sh" /usr/local/bin/time-clawshine
    # Inject TC_ROOT so the installed script knows where to find config
    sed -i "s|^TC_ROOT=.*|TC_ROOT=\"$TC_ROOT\"|" /usr/local/bin/time-clawshine
    chmod 755 /usr/local/bin/time-clawshine
    # Backward-compat symlink (v2 name)
    ln -sf /usr/local/bin/time-clawshine /usr/local/bin/quick-backup-restore

    # --- Register scheduler (systemd preferred, cron fallback) ------------------
    echo ""
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
        echo "==> Registering systemd timer..."

        # Convert cron expression to systemd OnCalendar (best-effort for hourly)
        # Default: hourly at :05. For custom cron, fall back to cron.
        SYSTEMD_CALENDAR="*-*-* *:05:00"
        if [[ "$CRON_EXPR" == "5 * * * *" ]]; then
            SYSTEMD_CALENDAR="*-*-* *:05:00"
        elif [[ "$CRON_EXPR" =~ ^\*/([0-9]+)\ \*\ \*\ \*\ \*$ ]]; then
            SYSTEMD_CALENDAR="*-*-* *:00/${BASH_REMATCH[1]}:00"
        elif [[ "$CRON_EXPR" =~ ^([0-9]+)\ \*\ \*\ \*\ \*$ ]]; then
            SYSTEMD_CALENDAR="*-*-* *:${BASH_REMATCH[1]}:00"
        else
            echo "    WARN: Complex cron expression — using OnCalendar=hourly"
            SYSTEMD_CALENDAR="hourly"
        fi

        UNIT_DIR="/etc/systemd/system"

        cat > "$UNIT_DIR/time-clawshine.service" <<EOF
[Unit]
Description=Time Clawshine — encrypted incremental backup
After=network.target

[Service]
Type=oneshot
Environment=TC_CONFIG=$CONFIG_FILE
ExecStart=/usr/local/bin/time-clawshine
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
EOF

        cat > "$UNIT_DIR/time-clawshine.timer" <<EOF
[Unit]
Description=Time Clawshine — hourly backup timer

[Timer]
OnCalendar=$SYSTEMD_CALENDAR
Persistent=true
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
EOF

        systemctl daemon-reload
        systemctl enable --now time-clawshine.timer
        CRON_FILE="systemd: time-clawshine.timer ($SYSTEMD_CALENDAR)"
        echo "    Systemd timer enabled: $SYSTEMD_CALENDAR"

        # Remove cron if it exists (migrating to systemd)
        for legacy_cron in "/etc/cron.d/quick-backup-restore" "/etc/cron.d/time-clawshine"; do
            [[ -f "$legacy_cron" ]] && rm -f "$legacy_cron" && echo "    Removed legacy cron: $legacy_cron"
        done
    else
        echo "==> Registering cron job: [$CRON_EXPR]"
        CRON_FILE="/etc/cron.d/time-clawshine"
        cat > "$CRON_FILE" <<EOF
# Time Clawshine — hourly backup
# Generated by setup.sh on $(date)
# Edit schedule in config.yaml, then re-run setup.sh
$CRON_EXPR root TC_CONFIG=$CONFIG_FILE /usr/local/bin/time-clawshine >/dev/null 2>> $LOG_FILE
EOF
        chmod 644 "$CRON_FILE"
        echo "    Cron registered at: $CRON_FILE"
    fi

    # --- Configure logrotate ---------------------------------------------------
    echo ""
    echo "==> Configuring logrotate for $LOG_FILE..."
    LOGROTATE_FILE="/etc/logrotate.d/time-clawshine"
    cat > "$LOGROTATE_FILE" <<EOF
$LOG_FILE {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 640 root root
}
EOF
    chmod 644 "$LOGROTATE_FILE"
    echo "    Logrotate configured at: $LOGROTATE_FILE"

    # --- Restrict config.yaml permissions (may contain Telegram token) ----------
    chmod 600 "$CONFIG_FILE"
    echo "    config.yaml permissions set to 600"
fi

# --- Run initial backup to validate ----------------------------------------
if [[ "$SKIP_BACKUP" == "true" ]]; then
    echo ""
    echo "==> Skipping initial backup (--skip-backup flag set)"
else
    echo ""
    echo "==> Running initial backup to validate setup..."
    if TC_CONFIG="$CONFIG_FILE" "$TC_ROOT/bin/backup.sh"; then
        echo ""
        echo "    ✓ Initial backup successful"
    else
        echo ""
        echo "    ✗ Initial backup FAILED — check config.yaml and retry"
        exit 1
    fi
fi

# --- Summary ---------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║              Setup complete ✓                        ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Repository   : %-36s ║\n" "$REPO"
printf "║  Password     : %-36s ║\n" "$PASS_FILE"
printf "║  Cron         : %-36s ║\n" "$CRON_FILE"
printf "║  Log          : %-36s ║\n" "$LOG_FILE"
printf "║  Retention    : %-36s ║\n" "$KEEP_LAST snapshots"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Restore helper: sudo bin/restore.sh"
echo "  View snapshots: restic -r $REPO --password-file $PASS_FILE snapshots"
