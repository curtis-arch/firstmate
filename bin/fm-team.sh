#!/usr/bin/env bash
# bin/fm-team.sh - explicit shared-worktree team contract for Orca-backed tasks.
#
# A team task is an ordinary Orca ship/scout task (one coordinator terminal,
# firstmate's direct report, unchanged) plus explicitly added teammate panes in
# the SAME Orca-managed task worktree. Teammates are task-owned plural durable
# identities recorded in the task's meta, never separate direct reports:
#
#   team_edit_policy=coordinator-only   the only supported concurrent-edit
#                                       policy (see below)
#   orca_team_pane_keys=<pk> [<pk>...]  authoritative durable pane identities
#   orca_team_terminals=<h> [<h>...]    runtime-epoch handle cache, same order
#
# Concurrent-edit policy: firstmate does not pretend multiple writers in one
# worktree are safe. The coordinator terminal owns every file edit, git stage,
# and commit; teammate panes are advisory (review, test runs, investigation)
# and must report findings back as text. Every `add --command ...` waits for
# the teammate agent and delivers this contract before any optional brief; the
# existing teardown dirty/unlanded checks on the single task worktree remain
# the backstop for violations.
#
# Fail-closed rules:
#   - add refuses unless the task meta exists, is active (no lifecycle claim),
#     records backend=orca with an orca_worktree_id, and is not a secondmate.
#   - add requires the verified creation shape (result.terminal.handle plus a
#     valid result.terminal.paneKey, observed on Orca 1.4.141); a creation
#     without a durable pane key is closed and the add aborts, because a
#     teammate is only addressable by its pane key.
#   - recording is CAS: a concurrent teardown claim, generation change, or
#     racing add makes the meta write refuse, and the just-created pane is
#     closed rather than leaked.
#   - status/close resolve pane keys through worktree-scoped `terminal list`
#     joined by `terminal show` (list tab/leaf ids are non-joinable `pty:`
#     placeholders); zero matches after clean enumeration is `gone`, anything
#     ambiguous is `unknown`/refused.
#   - steering ownership: `fm-send.sh <id>` continues to address ONLY the
#     coordinator terminal. Teammates are addressed only through this script.
#
# Usage:
#   fm-team.sh add <task-id> [--title <title>] [--command <cmd>] [--brief-file <path>]
#   fm-team.sh status <task-id>
#   fm-team.sh close <task-id> <pane-key>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
# shellcheck source=bin/fm-meta-lib.sh
. "$FM_ROOT/bin/fm-meta-lib.sh"
# shellcheck source=bin/backends/orca.sh
. "$FM_ROOT/bin/backends/orca.sh"
"$FM_ROOT/bin/fm-guard.sh" || true

usage() {
  sed -n '/^# Usage:/,/^set -eu/p' "$SCRIPT_DIR/fm-team.sh" | sed 's/^# \{0,1\}//; /^set -eu/d'
}

CMD=${1:-}
ID=${2:-}
[ -n "$CMD" ] && [ -n "$ID" ] || { usage >&2; exit 1; }
shift 2
META="$STATE/$ID.meta"

require_team_capable_meta() {
  [ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; return 1; }
  fm_meta_is_active_unlocked "$META" || { echo "error: task $ID has a lifecycle claim (teardown in progress); refusing team operation" >&2; return 1; }
  local backend kind
  backend=$(grep '^backend=' "$META" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  [ "$backend" = orca ] || { echo "error: task $ID is backend=${backend:-tmux}; shared-worktree teams are only supported on backend=orca" >&2; return 1; }
  kind=$(grep '^kind=' "$META" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  [ "$kind" != secondmate ] || { echo "error: task $ID is a secondmate; teams attach only to ship/scout tasks" >&2; return 1; }
  WORKTREE_ID=$(grep '^orca_worktree_id=' "$META" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  [ -n "$WORKTREE_ID" ] || { echo "error: task $ID records no orca_worktree_id; cannot own team panes" >&2; return 1; }
  GENERATION=$(fm_meta_value_unlocked "$META" generation)
  [ -n "$GENERATION" ] || { echo "error: task $ID records no generation; refusing team operation" >&2; return 1; }
}

team_add() {
  local title='' command='' brief_file=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --title) title=${2:?--title requires a value}; shift 2 ;;
      --command) command=${2:?--command requires a value}; shift 2 ;;
      --brief-file) brief_file=${2:?--brief-file requires a value}; shift 2 ;;
      *) echo "error: unknown add option '$1'" >&2; return 1 ;;
    esac
  done
  if [ -n "$brief_file" ]; then
    [ -n "$command" ] || { echo "error: --brief-file requires --command (a brief needs an agent to receive it)" >&2; return 1; }
    [ -f "$brief_file" ] || { echo "error: no brief at $brief_file" >&2; return 1; }
  fi
  require_team_capable_meta || return 1
  fm_backend_orca_runtime_check || return 1
  local existing_keys n out terminal pane_key state
  existing_keys=$(fm_backend_orca_team_pane_keys "$META")
  n=1
  if [ -n "$existing_keys" ]; then
    n=$(($(printf '%s\n' "$existing_keys" | wc -w | tr -d ' ') + 1))
  fi
  [ -n "$title" ] || title="fm-$ID-mate-$n"
  if [ -n "$command" ]; then
    out=$(orca terminal create --worktree "id:$WORKTREE_ID" --title "$title" --command "$command" --json) || return 1
  else
    out=$(orca terminal create --worktree "id:$WORKTREE_ID" --title "$title" --json) || return 1
  fi
  printf '%s' "$out" | fm_backend_orca_json_ok || return 1
  terminal=$(printf '%s' "$out" | fm_backend_orca_json_get terminal-handle 2>/dev/null || true)
  pane_key=$(printf '%s' "$out" | fm_backend_orca_json_get terminal-pane-key 2>/dev/null || true)
  if [ -z "$terminal" ]; then
    echo "error: orca terminal create did not return a verified terminal handle; no teammate recorded" >&2
    return 1
  fi
  if ! fm_backend_orca_pane_key_valid "$pane_key"; then
    echo "error: orca terminal create did not return a valid pane key for $title; closing the unaddressable pane and refusing to record it" >&2
    orca terminal close --terminal "$terminal" --json >/dev/null 2>&1 || true
    return 1
  fi
  if ! fm_backend_orca_meta_team_append "$META" "$GENERATION" "$existing_keys" "$pane_key" "$terminal"; then
    echo "error: task $ID meta changed during teammate creation; closing the just-created pane instead of leaking it" >&2
    orca terminal close --terminal "$terminal" --json >/dev/null 2>&1 || true
    return 1
  fi
  echo "team: recorded teammate pane $pane_key (terminal $terminal, title $title) for $ID"
  if [ -n "$command" ]; then
    if ! orca terminal wait --terminal "$terminal" --for tui-idle --timeout-ms 60000 --json >/dev/null 2>&1; then
      team_abort_uncontracted_pane "$pane_key" "$terminal" "teammate agent did not reach tui-idle within 60s"
      return 1
    fi
    local preamble brief
    preamble="Team contract for task $ID: this pane shares the task worktree with the coordinator. The coordinator terminal owns ALL file edits, git staging, and commits (team_edit_policy=coordinator-only). Do not modify files or run state-changing git commands; report findings back as text."
    brief=$preamble
    if [ -n "$brief_file" ]; then
      brief="$preamble

$(cat "$brief_file")"
    fi
    state=$(fm_backend_orca_send_text_submit "$terminal" "$brief" 5 1 1 "")
    if [ "$state" != empty ]; then
      team_abort_uncontracted_pane "$pane_key" "$terminal" "teammate contract submission reported '$state'"
      return 1
    fi
    echo "team: delivered coordinator-only edit contract to $pane_key"
  fi
}

team_close_recorded_pane() {
  local pane_key=$1 handle=${2:-} resolved rc
  if [ -z "$handle" ]; then
    if resolved=$(fm_backend_orca_team_resolve_pane "$WORKTREE_ID" "$pane_key"); then
      handle=${resolved%%$'\t'*}
    else
      rc=$?
      [ "$rc" -eq 2 ] || return 1
    fi
  fi
  if [ -n "$handle" ]; then
    orca terminal close --terminal "$handle" --json >/dev/null 2>&1 || true
    if fm_backend_orca_team_resolve_pane "$WORKTREE_ID" "$pane_key" >/dev/null 2>&1; then
      return 1
    else
      rc=$?
    fi
    [ "$rc" -eq 2 ] || return 1
  fi
  fm_backend_orca_meta_team_remove "$META" "$GENERATION" "$pane_key"
}

team_abort_uncontracted_pane() {
  local pane_key=$1 handle=$2 reason=$3
  if team_close_recorded_pane "$pane_key" "$handle"; then
    echo "error: $reason; closed and removed uncontracted teammate pane $pane_key" >&2
  else
    echo "error: $reason; could not verify teammate pane $pane_key absent, so it remains recorded" >&2
  fi
  return 1
}

team_status() {
  require_team_capable_meta || return 1
  local keys key state coordinator_terminal coordinator_pane
  coordinator_terminal=$(grep '^terminal=' "$META" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  coordinator_pane=$(grep '^orca_pane_key=' "$META" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  printf 'coordinator\t%s\t%s\t%s\n' "${coordinator_pane:-?}" "${coordinator_terminal:-?}" \
    "$(fm_backend_orca_agent_snapshot "$coordinator_terminal" "$WORKTREE_ID" "$META")"
  keys=$(fm_backend_orca_team_pane_keys "$META")
  [ -n "$keys" ] || { echo "team: no teammate panes recorded for $ID"; return 0; }
  for key in $keys; do
    state=$(fm_backend_orca_team_pane_state "$WORKTREE_ID" "$key")
    printf 'teammate\t%s\t%s\n' "$key" "$state"
  done
}

team_close() {
  local pane_key=${1:-}
  [ -n "$pane_key" ] || { echo "error: close needs the teammate pane key to close" >&2; return 1; }
  require_team_capable_meta || return 1
  local keys resolved rc handle
  keys=$(fm_backend_orca_team_pane_keys "$META")
  fm_backend_orca_team_list_contains "$keys" "$pane_key" || {
    echo "error: pane $pane_key is not a recorded teammate of $ID" >&2
    return 1
  }
  if resolved=$(fm_backend_orca_team_resolve_pane "$WORKTREE_ID" "$pane_key"); then
    handle=${resolved%%$'\t'*}
    team_close_recorded_pane "$pane_key" "$handle" || {
      echo "error: teammate pane $pane_key could not be verified closed; leaving it recorded" >&2
      return 1
    }
  else
    rc=$?
    [ "$rc" -eq 2 ] || { echo "error: teammate pane $pane_key is unresolved (ambiguous); refusing to drop the record" >&2; return 1; }
    team_close_recorded_pane "$pane_key" || return 1
  fi
  echo "team: closed and removed teammate pane $pane_key from $ID"
}

case "$CMD" in
  add) team_add "$@" ;;
  status) team_status "$@" ;;
  close) team_close "$@" ;;
  *) usage >&2; exit 1 ;;
esac
