#!/bin/bash
# =============================================================================
# bin/restore.sh — Time Clawshine interactive restore helper
# Usage: sudo bin/restore.sh [snapshot_id] [--file path] [--target dir]
# =============================================================================

set -uo pipefail

TC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$TC_ROOT/lib.sh"

tc_check_deps
tc_load_config

SNAPSHOT_ID=""
FILE_FILTER="${TC_FILE:-}"
TARGET="${TC_TARGET:-/}"

# --- Parse flags ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)   FILE_FILTER="$2"; shift 2 ;;
        --target) TARGET="$2";      shift 2 ;;
        --help|-h)
            echo "Usage: sudo bin/restore.sh [snapshot_id] [--file path] [--target dir]"
            echo ""
            echo "  snapshot_id   Restic snapshot ID (or 'latest'). Omit to pick interactively."
            echo "  --file path   Restore only this file/directory"
            echo "  --target dir  Restore to this directory (default: /)"
            echo ""
            echo "Examples:"
            echo "  sudo bin/restore.sh                          # interactive"
            echo "  sudo bin/restore.sh latest                   # restore latest to /"
            echo "  sudo bin/restore.sh abc123 --target /tmp/r   # restore snapshot to /tmp/r"
            echo "  sudo bin/restore.sh latest --file /root/.openclaw/workspace/MEMORY.md"
            exit 0
            ;;
        -*) echo "Unknown flag: $1"; exit 1 ;;
        *)  SNAPSHOT_ID="$1"; shift ;;
    esac
done

echo "╔══════════════════════════════════════╗"
echo "║    Time Clawshine — Restore          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# --- Show available snapshots -----------------------------------------------
echo "Available snapshots:"
echo ""
restic_cmd snapshots --compact
echo ""

# --- Pick snapshot interactively if not provided ----------------------------
if [[ -z "$SNAPSHOT_ID" ]]; then
    read -rp "Snapshot ID (or 'latest'): " SNAPSHOT_ID
    [[ -z "$SNAPSHOT_ID" ]] && { echo "Aborted."; exit 0; }
fi

# --- Build restore args -----------------------------------------------------
RESTORE_ARGS=(restore "$SNAPSHOT_ID" --target "$TARGET")
[[ -n "$FILE_FILTER" ]] && RESTORE_ARGS+=(--include "$FILE_FILTER")

# --- Dry run first ----------------------------------------------------------
echo ""
echo "==> Dry run preview:"
echo ""
restic_cmd "${RESTORE_ARGS[@]}" --dry-run 2>&1 | head -40
echo ""

read -rp "Proceed with restore? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# --- Real restore -----------------------------------------------------------
echo ""
echo "==> Restoring snapshot $SNAPSHOT_ID to $TARGET ..."
restic_cmd "${RESTORE_ARGS[@]}"

echo ""
echo "✓ Restore complete."
[[ "$TARGET" != "/" ]] && echo "  Files restored to: $TARGET"
