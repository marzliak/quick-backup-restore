#!/bin/bash
# =============================================================================
# bin/test.sh — Time Clawshine self-test (backup → restore → verify roundtrip)
# Creates a temporary repo, backs up test data, restores, and verifies integrity.
# Usage: bin/test.sh (does NOT require root — uses temp directories)
# =============================================================================

set -euo pipefail

TC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Parse flags ------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: bin/test.sh"
            echo ""
            echo "Runs the Time Clawshine self-test suite:"
            echo "  - Dependency checks"
            echo "  - Config validation"
            echo "  - Shell syntax checks on all scripts"
            echo "  - Backup → restore → verify roundtrip"
            echo ""
            echo "Does NOT require root — uses temp directories."
            echo "Exit code: 0 if all tests pass, 1 if any fail."
            exit 0
            ;;
    esac
done

# --- Colors (if supported) --------------------------------------------------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; NC=''
fi

PASS=0
FAIL=0
TESTS=0

_test() {
    local name="$1"
    TESTS=$(( TESTS + 1 ))
    echo -n "  [$TESTS] $name ... "
}

_ok() {
    PASS=$(( PASS + 1 ))
    echo -e "${GREEN}OK${NC}"
}

_fail() {
    FAIL=$(( FAIL + 1 ))
    echo -e "${RED}FAIL${NC}: $1"
}

echo "╔═════════════════════════════════════════════════════╗"
echo "║          Time Clawshine — Self Test                  ║"
echo "╚═════════════════════════════════════════════════════╝"
echo ""

# --- Check dependencies ----------------------------------------------------
_test "Dependencies available"
MISSING=()
for cmd in restic yq curl jq bash openssl; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    _fail "missing: ${MISSING[*]}"
else
    _ok
fi

# --- Validate config.yaml syntax -------------------------------------------
_test "config.yaml is valid YAML"
if yq e '.' "$TC_ROOT/config.yaml" > /dev/null 2>&1; then
    _ok
else
    _fail "yq cannot parse config.yaml"
fi

# --- Validate config loads without error ------------------------------------
_test "Config loads and validates"
CONFIG_OUTPUT=$(bash -c "export TC_SKIP_PASS_CHECK=true; source '$TC_ROOT/lib.sh'; tc_load_config" 2>&1) && _ok || _fail "$CONFIG_OUTPUT"

# --- Validate skill.json is valid JSON --------------------------------------
_test "skill.json is valid JSON"
if jq empty "$TC_ROOT/skill.json" 2>/dev/null; then
    _ok
else
    _fail "jq cannot parse skill.json"
fi

# --- Shell syntax checks on all scripts ------------------------------------
for script in lib.sh bin/backup.sh bin/setup.sh bin/restore.sh bin/status.sh bin/customize.sh bin/prune.sh bin/test.sh bin/uninstall.sh; do
    _test "Syntax check: $script"
    if [[ -f "$TC_ROOT/$script" ]]; then
        if bash -n "$TC_ROOT/$script" 2>/dev/null; then
            _ok
        else
            _fail "bash -n failed"
        fi
    else
        _fail "file not found"
    fi
done

# --- --help flag exits 0 on all scripts ------------------------------------
for script in bin/backup.sh bin/setup.sh bin/restore.sh bin/status.sh bin/customize.sh bin/prune.sh bin/test.sh bin/uninstall.sh; do
    _test "--help exits 0: $script"
    if bash "$TC_ROOT/$script" --help > /dev/null 2>&1; then
        _ok
    else
        _fail "--help returned non-zero"
    fi
done

# --- Backup → Restore → Verify roundtrip -----------------------------------
_test "Roundtrip: backup → restore → verify"

TMPDIR=$(mktemp -d)
TEST_REPO="$TMPDIR/repo"
TEST_PASS="$TMPDIR/pass"
TEST_DATA="$TMPDIR/data"
TEST_RESTORE="$TMPDIR/restore"

mkdir -p "$TEST_DATA/subdir"
echo "Time Clawshine test file — $(date)" > "$TEST_DATA/testfile.txt"
echo "Nested content" > "$TEST_DATA/subdir/nested.txt"
dd if=/dev/urandom of="$TEST_DATA/subdir/binary.bin" bs=1024 count=4 2>/dev/null

# Generate password
openssl rand -base64 32 > "$TEST_PASS"
chmod 600 "$TEST_PASS"

# Init repo
if RESTIC_PASSWORD_FILE="$TEST_PASS" restic init -r "$TEST_REPO" > /dev/null 2>&1; then
    # Backup
    if RESTIC_PASSWORD_FILE="$TEST_PASS" restic backup -r "$TEST_REPO" "$TEST_DATA" > /dev/null 2>&1; then
        # Restore
        mkdir -p "$TEST_RESTORE"
        if RESTIC_PASSWORD_FILE="$TEST_PASS" restic restore latest -r "$TEST_REPO" --target "$TEST_RESTORE" > /dev/null 2>&1; then
            # Verify files match (use relative paths so hashes compare equal)
            ORIG_HASH=$(cd "$TEST_DATA" && find . -type f -exec sha256sum {} \; | sort | sha256sum)
            # Restored files are under $TEST_RESTORE/$TEST_DATA
            RESTORED_DATA="$TEST_RESTORE$TEST_DATA"
            if [[ -d "$RESTORED_DATA" ]]; then
                REST_HASH=$(cd "$RESTORED_DATA" && find . -type f -exec sha256sum {} \; | sort | sha256sum)
                if [[ "$ORIG_HASH" == "$REST_HASH" ]]; then
                    _ok
                else
                    _fail "hash mismatch after restore"
                fi
            else
                _fail "restored data directory not found at $RESTORED_DATA"
            fi
        else
            _fail "restic restore failed"
        fi
    else
        _fail "restic backup failed"
    fi

    # Check integrity
    _test "Roundtrip: restic check"
    if RESTIC_PASSWORD_FILE="$TEST_PASS" restic check -r "$TEST_REPO" > /dev/null 2>&1; then
        _ok
    else
        _fail "restic check failed"
    fi

    # Prune dry-run (should succeed without removing the single snapshot)
    _test "Roundtrip: prune --dry-run"
    if RESTIC_PASSWORD_FILE="$TEST_PASS" restic forget --keep-last 1 --prune --dry-run -r "$TEST_REPO" > /dev/null 2>&1; then
        _ok
    else
        _fail "restic forget --dry-run failed"
    fi

    # Verify password file permissions
    _test "Roundtrip: password file permissions"
    PASS_PERMS=$(stat -c '%a' "$TEST_PASS" 2>/dev/null || stat -f '%Lp' "$TEST_PASS" 2>/dev/null || echo "?")
    if [[ "$PASS_PERMS" == "600" ]]; then
        _ok
    else
        _fail "expected 600, got $PASS_PERMS"
    fi
else
    _fail "restic init failed"
fi

# Cleanup temp
rm -rf "$TMPDIR"

# --- Summary ----------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}All $TESTS tests passed ✓${NC}"
    EXIT_CODE=0
else
    echo -e "  ${RED}$FAIL/$TESTS tests failed ✗${NC}"
    EXIT_CODE=1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
exit $EXIT_CODE
