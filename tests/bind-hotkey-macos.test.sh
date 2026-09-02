#!/usr/bin/env bash
# ABOUTME: Tests the macOS binder's pbs parsing against captured `defaults read` output.
# ABOUTME: Runs anywhere, so the quoting assumptions are checked without a Mac round-trip.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../bind-hotkey-macos.sh
. "$SCRIPT_DIR/../bind-hotkey-macos.sh"

PASSED=0
FAILED=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASSED=$((PASSED + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$name"
    else
        FAILED=$((FAILED + 1))
        printf '  \033[31mFAIL\033[0m  %s\n        expected [%s], got [%s]\n' "$name" "$expected" "$actual"
    fi
}

# Captured verbatim from macOS 26.5.2. The inner key is quoted here; older systems
# emit it bare, so both forms are exercised.
fixture_other_owns_key() {
    cat <<'EOF'
{
    "(null) - Screenshot for Claude - runWorkflowAsService" =     {
        "key_equivalent" = "@$1";
        "presentation_modes" =         {
            ContextMenu = 1;
        };
    };
}
EOF
}

fixture_snapclip_bound() {
    cat <<'EOF'
{
    "(null) - Snapclip - runWorkflowAsService" =     {
        "key_equivalent" = "@$1";
    };
}
EOF
}

fixture_unquoted_inner_key() {
    cat <<'EOF'
{
    "(null) - Snapclip - runWorkflowAsService" =     {
        key_equivalent = "@$1";
    };
}
EOF
}

fixture_no_shortcuts() {
    cat <<'EOF'
{
    "(null) - Claude Code Here - runWorkflowAsService" =     {
        "presentation_modes" =         {
            ContextMenu = 1;
        };
    };
}
EOF
}

echo
echo "Conflict detection"

pbs_dump() { fixture_other_owns_key; }
check 'refuses when another service owns the key' 1 \
  "$(warn_on_shortcut_conflict 2>/dev/null; echo $?)"
# Capture first: under pipefail the pipeline would inherit the function's
# deliberate exit 1 and mask a successful match.
conflict_message="$(warn_on_shortcut_conflict 2>&1 >/dev/null)"
check 'names the service holding it' yes \
  "$(case "$conflict_message" in *'Screenshot for Claude'*) echo yes ;; *) echo no ;; esac)"
check 'tells you how to move Snapclip instead' yes \
  "$(case "$conflict_message" in *SNAPCLIP_KEY_EQUIVALENT*) echo yes ;; *) echo no ;; esac)"

pbs_dump() { fixture_no_shortcuts; }
check 'allows binding when nothing owns the key' 0 \
  "$(warn_on_shortcut_conflict 2>/dev/null; echo $?)"

pbs_dump() { fixture_snapclip_bound; }
check 'does not treat its own existing binding as a conflict' 0 \
  "$(warn_on_shortcut_conflict 2>/dev/null; echo $?)"

pbs_dump() { printf ''; }
check 'allows binding when pbs has no entries at all' 0 \
  "$(warn_on_shortcut_conflict 2>/dev/null; echo $?)"

echo
echo "Reading the recorded shortcut"

pbs_dump() { fixture_snapclip_bound; }
check 'reads our shortcut when bound' '@$1' "$(read_shortcut)"

pbs_dump() { fixture_unquoted_inner_key; }
check 'reads it when macOS leaves the inner key unquoted' '@$1' "$(read_shortcut)"

pbs_dump() { fixture_no_shortcuts; }
check 'reports nothing when we are not bound' '' "$(read_shortcut)"

# The dangerous direction: claiming a shortcut we do not have would let a cutover
# report success while the hotkey still belongs to something else.
pbs_dump() { fixture_other_owns_key; }
check 'never reports another service shortcut as ours' '' "$(read_shortcut)"

pbs_dump() { printf ''; }
check 'reports nothing when pbs is empty' '' "$(read_shortcut)"

echo
printf '%d passed, %d failed\n\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
