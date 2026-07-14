#!/usr/bin/env bash
# Record a PR-ready task: appends pr=<url> and GitHub's pr_head=<sha> to
# state/<id>.meta when available, then arms the watcher's merge poll by writing
# state/<id>.check.sh, which prints one line iff the PR is merged (the watcher's
# check contract: output = wake firstmate, silence = keep sleeping).
# Usage: fm-pr-check.sh <task-id> <pr-url>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
# shellcheck source=bin/fm-meta-lib.sh
. "$FM_ROOT/bin/fm-meta-lib.sh"
"$FM_ROOT/bin/fm-guard.sh" || true
ID=$1
URL=$2

META="$STATE/$ID.meta"
EXPECTED_IDENTITY=$(fm_meta_identity "$META") || {
  echo "error: no live metadata for task $ID at $META" >&2
  exit 1
}
WT=$(grep '^worktree=' "$META" | tail -1 | cut -d= -f2- || true)
PR_HEAD=
if [ -n "$WT" ] && [ -d "$WT" ]; then
  if command -v gh >/dev/null 2>&1; then
    if REMOTE_HEAD=$(cd "$WT" && gh pr view "$URL" --json headRefOid -q .headRefOid 2>/dev/null); then
      PR_HEAD=$REMOTE_HEAD
    fi
  fi
fi
META_STATUS=0
fm_meta_lock_acquire "$META" || exit 1
CURRENT_IDENTITY=$(fm_meta_identity_unlocked "$META" 2>/dev/null || true)
if [ -z "$CURRENT_IDENTITY" ] || [ "$CURRENT_IDENTITY" != "$EXPECTED_IDENTITY" ] || ! fm_meta_is_active_unlocked "$META"; then
  META_STATUS=1
else
  if ! grep -qxF "pr=$URL" "$META"; then
    echo "pr=$URL" >> "$META" || META_STATUS=$?
  fi
  if [ "$META_STATUS" -eq 0 ] && [ -n "$PR_HEAD" ] && ! grep -qxF "pr_head=$PR_HEAD" "$META"; then
    echo "pr_head=$PR_HEAD" >> "$META" || META_STATUS=$?
  fi
fi
if [ "$META_STATUS" -eq 0 ]; then
  if ! cat > "$STATE/$ID.check.sh" <<EOF
state=\$(gh pr view "$URL" --json state -q .state 2>/dev/null)
[ "\$state" = "MERGED" ] && echo "merged"
EOF
  then
    META_STATUS=1
  fi
fi
fm_meta_lock_release "$META"
[ "$META_STATUS" -eq 0 ] || {
  echo "error: task metadata changed or disappeared for $ID; PR state was not recorded" >&2
  exit "$META_STATUS"
}
echo "armed: state/$ID.check.sh polls $URL"
