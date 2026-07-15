#!/usr/bin/env bash
# bin/backends/orca.sh - the Orca terminal session-provider adapter.
#
# Orca owns both the task worktree and the terminal endpoint. Escape key support
# remains unsupported until Orca exposes a terminal-send primitive for it.
#
# Target string shape: the Orca terminal id accepted by `orca terminal ...`.

# Shared composer-content classifier (empty|pending|unknown, and the fleet-wide
# dead-shell-vs-agent-composer rule). Owned by bin/fm-composer-lib.sh, reused by
# every backend so the decision cannot drift.
# shellcheck source=bin/fm-composer-lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../fm-composer-lib.sh"
# shellcheck source=bin/fm-meta-lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../fm-meta-lib.sh"

fm_backend_orca_tool_check() {
  command -v orca >/dev/null 2>&1 || { echo "error: backend=orca selected but the 'orca' CLI is not installed" >&2; return 1; }
}

fm_backend_orca_runtime_check() {
  fm_backend_orca_tool_check || return 1
  local out
  out=$(orca status --json 2>/dev/null) || {
    echo "error: backend=orca selected but 'orca status --json' failed; start Orca and wait for the runtime to be ready" >&2
    return 1
  }
  # shellcheck disable=SC2016  # Single quotes are deliberate: ${...} belongs to the Node snippet.
  printf '%s' "$out" | node -e '
const fs = require("fs");
let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (err) {
  console.error("error: invalid Orca status JSON: " + err.message);
  process.exit(1);
}
if (data.ok === false) {
  const msg = data.error && (data.error.message || data.error.code);
  console.error("error: Orca runtime is not ready" + (msg ? ": " + msg : ""));
  process.exit(1);
}
const r = data.result || {};
const runtime = r.runtime || {};
const reachable = runtime.reachable ?? r.runtimeReachable;
const state = runtime.state || r.runtimeState || "";
if (reachable === true && state === "ready") process.exit(0);
console.error(`error: backend=orca requires a ready Orca runtime (reachable=${String(reachable)}, state=${state || "unknown"})`);
process.exit(1);
'
}

fm_backend_orca_json_get() {  # <field> ; fields: worktree-id worktree-path terminal-handle worktree-terminal-handle terminal-pane-key repo-id
  # Terminal handles are accepted only from verified terminal result shapes:
  # result.terminal or a root terminal object with .handle. Undocumented
  # result.id and result.worktree.terminal shapes are ignored until a real Orca
  # smoke run proves them.
  local field=$1
  node -e '
const fs = require("fs");
const field = process.argv[1];
const data = JSON.parse(fs.readFileSync(0, "utf8"));
if (data.ok === false) {
  const msg = data.error && (data.error.message || data.error.code);
  if (msg) console.error(msg);
  process.exit(2);
}
const r = data.result || {};
const wt = r.worktree || r.item || r;
const explicitTerm = r.terminal || null;
const repo = r.repo || r.repository || r;
function scalar(v) {
  return (typeof v === "string" || typeof v === "number") ? String(v) : "";
}
function handle(obj) {
  if (!obj) return "";
  if (typeof obj === "string" || typeof obj === "number") return String(obj);
  return scalar(obj.handle) || "";
}
let v = "";
if (field === "worktree-id") v = wt.id || wt.worktreeId || r.worktreeId || "";
if (field === "worktree-path") v = wt.path || (wt.git && wt.git.path) || r.path || "";
if (field === "terminal-handle") v = handle(explicitTerm || r) || "";
if (field === "worktree-terminal-handle") v = handle(explicitTerm) || "";
if (field === "terminal-pane-key") v = scalar((explicitTerm || r).paneKey) || "";
if (field === "repo-id") v = repo.id || repo.repoId || r.repoId || "";
if (!v) process.exit(1);
process.stdout.write(String(v));
' "$field"
}

fm_backend_orca_json_ok() {
  node -e '
const fs = require("fs");
const input = fs.readFileSync(0, "utf8").trim();
if (!input) process.exit(0);
let data;
try {
  data = JSON.parse(input);
} catch (err) {
  console.error("invalid Orca JSON: " + err.message);
  process.exit(2);
}
if (data.ok === false) {
  const msg = data.error && (data.error.message || data.error.code);
  if (msg) console.error(msg);
  process.exit(2);
}
'
}

fm_backend_orca_run_json() {
  local out
  out=$("$@") || return 1
  printf '%s' "$out" | fm_backend_orca_json_ok
}

# paneKey is Orca's canonical remint-stable identity: one UUID tab id and one
# UUID leaf id separated by exactly one colon.
fm_backend_orca_pane_key_valid() {  # <pane-key>
  local pane_key=${1:-} uuid='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
  [[ "$pane_key" =~ ^${uuid}:${uuid}$ ]]
}

# Normalize the terminal-show fields needed by both semantic liveness and
# reminted-handle recovery. Shape validation stays separate from lifecycle
# policy so recovery can distinguish a connected match from a disconnected one.
fm_backend_orca_terminal_record() {  # <terminal-show-json>
  printf '%s' "$1" | node -e '
const fs = require("fs");
let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (_) {
  process.exit(1);
}
if (data.ok !== true || !data.result || !data.result.terminal) process.exit(1);
const terminal = data.result.terminal;
const fields = [terminal.worktreeId, terminal.tabId, terminal.leafId];
if (!fields.every((value) => typeof value === "string" && value.length > 0)) process.exit(1);
if (typeof terminal.connected !== "boolean" || typeof terminal.writable !== "boolean") process.exit(1);
process.stdout.write(terminal.worktreeId + "\t" + terminal.tabId + ":" + terminal.leafId + "\t" + terminal.connected + "\t" + terminal.writable);
'
}

# `terminal show`, not `terminal list`, owns the P1 join because CLI-created
# terminals can expose non-joinable `pty:` placeholders in list results.
fm_backend_orca_terminal_identity() {  # <terminal-show-json>
  local record worktree_id rest pane_key connected writable
  record=$(fm_backend_orca_terminal_record "$1" 2>/dev/null) || return 1
  worktree_id=${record%%$'\t'*}
  rest=${record#*$'\t'}
  pane_key=${rest%%$'\t'*}
  rest=${rest#*$'\t'}
  connected=${rest%%$'\t'*}
  writable=${rest#*$'\t'}
  fm_backend_orca_pane_key_valid "$pane_key" || return 1
  [ "$connected" = true ] && [ "$writable" = true ] || return 1
  printf '%s\t%s' "$worktree_id" "$pane_key"
}

fm_backend_orca_capture_pane_key() {  # <terminal-id> <worktree-id> [creation-json]
  local terminal=$1 worktree_id=$2 creation_json=${3:-} pane_key show_out record shown_worktree rest
  if [ -n "$creation_json" ]; then
    pane_key=$(printf '%s' "$creation_json" | fm_backend_orca_json_get terminal-pane-key 2>/dev/null || true)
    if fm_backend_orca_pane_key_valid "$pane_key"; then
      printf '%s' "$pane_key"
      return 0
    fi
  fi
  show_out=$(orca terminal show --terminal "$terminal" --json 2>/dev/null) || return 1
  record=$(fm_backend_orca_terminal_record "$show_out" 2>/dev/null) || return 1
  shown_worktree=${record%%$'\t'*}
  rest=${record#*$'\t'}
  pane_key=${rest%%$'\t'*}
  [ "$shown_worktree" = "$worktree_id" ] || return 1
  fm_backend_orca_pane_key_valid "$pane_key" || return 1
  printf '%s' "$pane_key"
}

fm_backend_orca_json_error_code() {  # <json>
  printf '%s' "$1" | node -e '
const fs = require("fs");
let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (_) {
  process.exit(1);
}
if (data.ok !== false || !data.error || typeof data.error.code !== "string") process.exit(1);
process.stdout.write(data.error.code);
'
}

fm_backend_orca_json_terminal_handles() {  # <terminal-list-json>
  printf '%s' "$1" | node -e '
const fs = require("fs");
let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (_) {
  process.exit(1);
}
if (data.ok !== true || !data.result || !Array.isArray(data.result.terminals)) process.exit(1);
const handles = data.result.terminals.map((terminal) => terminal && terminal.handle);
if (!handles.every((handle) => typeof handle === "string" && handle.length > 0 && !handle.includes("\n"))) process.exit(1);
process.stdout.write(handles.join("\n"));
'
}

fm_backend_orca_meta_identity() {  # <meta-path>
  local meta=$1 terminal worktree_id pane_key generation status=0
  fm_meta_lock_acquire "$meta" || return 1
  if [ -f "$meta" ] && fm_meta_is_active_unlocked "$meta"; then
    terminal=$(grep '^terminal=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    worktree_id=$(grep '^orca_worktree_id=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    pane_key=$(grep '^orca_pane_key=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    generation=$(fm_meta_value_unlocked "$meta" generation)
  else
    status=1
  fi
  fm_meta_lock_release "$meta"
  [ "$status" -eq 0 ] || return "$status"
  printf '%s\t%s\t%s\t%s' "$terminal" "$worktree_id" "$pane_key" "$generation"
}

fm_backend_orca_meta_set_terminal() {  # <meta-path> <expected-terminal> <expected-worktree-id> <expected-pane-key> <expected-generation> <terminal-handle>
  local meta=$1 expected_terminal=$2 expected_worktree_id=$3 expected_pane_key=$4 expected_generation=$5 terminal=$6
  local current_terminal current_worktree_id current_pane_key current_generation tmp status=0
  fm_meta_lock_acquire "$meta" || return 1
  if [ -f "$meta" ] && fm_meta_is_active_unlocked "$meta"; then
    current_terminal=$(grep '^terminal=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    current_worktree_id=$(grep '^orca_worktree_id=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    current_pane_key=$(grep '^orca_pane_key=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    current_generation=$(fm_meta_value_unlocked "$meta" generation)
    [ "$current_terminal" = "$expected_terminal" ] || status=1
    [ "$current_worktree_id" = "$expected_worktree_id" ] || status=1
    [ "$current_pane_key" = "$expected_pane_key" ] || status=1
    [ "$current_generation" = "$expected_generation" ] || status=1
  else
    status=1
  fi
  tmp="$meta.tmp.$$"
  if [ "$status" -eq 0 ]; then
    awk -v terminal="$terminal" '
    BEGIN { written = 0 }
    /^terminal=/ {
      if (!written) print "terminal=" terminal
      written = 1
      next
    }
    { print }
    END { if (!written) print "terminal=" terminal }
  ' "$meta" > "$tmp" || status=$?
  fi
  if [ "$status" -eq 0 ]; then
    mv "$tmp" "$meta" || status=$?
  else
    rm -f "$tmp"
  fi
  fm_meta_lock_release "$meta"
  return "$status"
}

# Resolve the remint-stable pane identity inside exactly one recorded worktree.
# Every candidate is shown before any decision; one unreadable candidate makes
# the entire attempt unresolved because it could be the true match.
fm_backend_orca_recover_terminal() {  # <meta-path> <expected-terminal> <expected-worktree-id> <expected-pane-key> <expected-generation>
  local meta=${1:-} expected_terminal=$2 worktree_id=$3 pane_key=$4 expected_generation=$5 list_out handles handle show_out record candidate_worktree rest candidate_pane connected unresolved=0
  local -a matches=() connected_matches=()
  if [ -z "$worktree_id" ] || ! fm_backend_orca_pane_key_valid "$pane_key"; then
    echo "error: Orca endpoint recovery unavailable: missing or invalid orca_worktree_id/orca_pane_key in $meta" >&2
    return 1
  fi
  list_out=$(orca terminal list --worktree "id:$worktree_id" --json 2>/dev/null) || {
    echo "error: Orca endpoint recovery unresolved: terminal list failed for recorded worktree $worktree_id" >&2
    return 1
  }
  handles=$(fm_backend_orca_json_terminal_handles "$list_out" 2>/dev/null) || {
    echo "error: Orca endpoint recovery unresolved: invalid terminal list for recorded worktree $worktree_id" >&2
    return 1
  }
  while IFS= read -r handle; do
    [ -n "$handle" ] || continue
    show_out=$(orca terminal show --terminal "$handle" --json 2>/dev/null) || {
      echo "error: Orca endpoint recovery unresolved: candidate $handle could not be shown" >&2
      unresolved=1
      continue
    }
    record=$(fm_backend_orca_terminal_record "$show_out" 2>/dev/null) || {
      echo "error: Orca endpoint recovery unresolved: candidate $handle returned an invalid terminal shape" >&2
      unresolved=1
      continue
    }
    candidate_worktree=${record%%$'\t'*}
    rest=${record#*$'\t'}
    candidate_pane=${rest%%$'\t'*}
    rest=${rest#*$'\t'}
    connected=${rest%%$'\t'*}
    fm_backend_orca_pane_key_valid "$candidate_pane" || {
      echo "error: Orca endpoint recovery unresolved: candidate $handle returned an invalid pane key" >&2
      unresolved=1
      continue
    }
    if [ "$candidate_worktree" = "$worktree_id" ] && [ "$candidate_pane" = "$pane_key" ]; then
      matches+=("$handle")
      connected_matches+=("$connected")
    fi
  done <<< "$handles"
  [ "$unresolved" -eq 0 ] || return 1
  case "${#matches[@]}" in
    0)
      echo "error: Orca endpoint gone: no terminal matches pane $pane_key in recorded worktree $worktree_id" >&2
      return 1
      ;;
    1)
      if [ "${connected_matches[0]}" != true ]; then
        echo "error: Orca endpoint disconnected: terminal ${matches[0]} matches pane $pane_key but is not connected" >&2
        return 1
      fi
      fm_backend_orca_meta_set_terminal "$meta" "$expected_terminal" "$worktree_id" "$pane_key" "$expected_generation" "${matches[0]}" || {
        echo "error: Orca endpoint recovery found ${matches[0]} but could not update $meta" >&2
        return 1
      }
      printf '%s' "${matches[0]}"
      ;;
    *)
      echo "error: Orca endpoint recovery ambiguous for pane $pane_key: ${matches[*]}" >&2
      return 1
      ;;
  esac
}

fm_backend_orca_raw_terminal_show() { orca terminal show --terminal "$1" --json; }
fm_backend_orca_raw_terminal_read() { local terminal=$1; shift; orca terminal read --terminal "$terminal" "$@" --json; }
fm_backend_orca_raw_send_line() { orca terminal send --terminal "$1" --text "$2" --enter --json; }
fm_backend_orca_raw_send_literal() { orca terminal send --terminal "$1" --text "$2" --json; }
fm_backend_orca_raw_send_enter() { orca terminal send --terminal "$1" --text "" --enter --json; }
fm_backend_orca_raw_send_interrupt() { orca terminal send --terminal "$1" --interrupt --json; }
fm_backend_orca_raw_close() { orca terminal close --terminal "$1" --json; }

# Run one handle operation and retry it once only when the first result carries
# the exact terminal_handle_stale code and metadata resolves one replacement.
fm_backend_orca_with_recovery() {  # <meta-path-or-empty> <terminal-id> <raw-fn> [args...]
  local meta=${1:-} terminal=$2 fn=$3 out status code recovered identity rest expected_terminal worktree_id pane_key generation
  shift 3
  if [ -n "$meta" ] && [ -f "$meta" ]; then
    identity=$(fm_backend_orca_meta_identity "$meta" 2>/dev/null || true)
    expected_terminal=${identity%%$'\t'*}
    rest=${identity#*$'\t'}
    worktree_id=${rest%%$'\t'*}
    rest=${rest#*$'\t'}
    pane_key=${rest%%$'\t'*}
    generation=${rest#*$'\t'}
    [ -z "$expected_terminal" ] || terminal=$expected_terminal
  fi
  if out=$("$fn" "$terminal" "$@" 2>/dev/null); then status=0; else status=$?; fi
  if [ "$status" -eq 0 ] && printf '%s' "$out" | fm_backend_orca_json_ok >/dev/null 2>&1; then
    printf '%s' "$out"
    return 0
  fi
  code=$(fm_backend_orca_json_error_code "$out" 2>/dev/null || true)
  if [ "$code" != terminal_handle_stale ] || [ -z "$meta" ]; then
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    return 1
  fi
  if [ -z "${expected_terminal:-}" ] || [ -z "${worktree_id:-}" ] || ! fm_backend_orca_pane_key_valid "${pane_key:-}"; then
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    return 1
  fi
  recovered=$(fm_backend_orca_recover_terminal "$meta" "$expected_terminal" "$worktree_id" "$pane_key" "${generation:-}") || return 1
  echo "info: recovered Orca terminal handle $terminal -> $recovered" >&2
  if out=$("$fn" "$recovered" "$@" 2>/dev/null); then status=0; else status=$?; fi
  [ "$status" -eq 0 ] || return 1
  printf '%s' "$out" | fm_backend_orca_json_ok >/dev/null 2>&1 || return 1
  printf '%s' "$out"
}

# fm_backend_orca_agent_snapshot: resolve one recorded endpoint to one agent in
# one recorded worktree. Every rejected or unreadable shape normalizes to
# `unknown`; only E1b-observed working/done/no-agent shapes are returned.
fm_backend_orca_agent_snapshot() {  # <terminal-id> <recorded-worktree-id> [meta-path]
  local terminal=${1:-} worktree_id=${2:-} meta=${3:-} show_out identity shown_worktree pane_key ps_out snapshot
  [ -n "$terminal" ] && [ -n "$worktree_id" ] || { printf 'unknown'; return 0; }
  fm_backend_orca_tool_check >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  show_out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_terminal_show 2>/dev/null) || { printf 'unknown'; return 0; }
  identity=$(fm_backend_orca_terminal_identity "$show_out" 2>/dev/null) || { printf 'unknown'; return 0; }
  shown_worktree=${identity%%$'\t'*}
  pane_key=${identity#*$'\t'}
  [ "$shown_worktree" = "$worktree_id" ] || { printf 'unknown'; return 0; }
  ps_out=$(orca worktree ps --json 2>/dev/null) || { printf 'unknown'; return 0; }
  snapshot=$(printf '%s' "$ps_out" | node -e '
const fs = require("fs");
const worktreeId = process.argv[1];
const paneKey = process.argv[2];
let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (_) {
  process.exit(1);
}
if (data.ok !== true || !data.result || !Array.isArray(data.result.worktrees)) process.exit(1);
const worktrees = data.result.worktrees.filter((worktree) => worktree && worktree.worktreeId === worktreeId);
if (worktrees.length !== 1 || !Array.isArray(worktrees[0].agents)) process.exit(1);
if (!worktrees[0].agents.every((agent) => agent && typeof agent === "object" && typeof agent.paneKey === "string" && agent.paneKey.length > 0 && typeof agent.state === "string" && agent.state.length > 0)) process.exit(1);
if (worktrees[0].agents.length === 0) {
  process.stdout.write("no-agent");
  process.exit(0);
}
const agents = worktrees[0].agents.filter((agent) => agent && agent.paneKey === paneKey);
if (agents.length !== 1) process.exit(1);
const state = agents[0].state;
if (state !== "working" && state !== "done") process.exit(1);
process.stdout.write(state);
' "$worktree_id" "$pane_key" 2>/dev/null) || { printf 'unknown'; return 0; }
  case "$snapshot" in
    working|done|no-agent) printf '%s' "$snapshot" ;;
    *) printf 'unknown' ;;
  esac
}

fm_backend_orca_busy_state() {  # <terminal-id> <recorded-worktree-id> [meta-path]
  case "$(fm_backend_orca_agent_snapshot "$@")" in
    working) printf 'busy' ;;
    done) printf 'idle' ;;
    *) printf 'unknown' ;;
  esac
}

fm_backend_orca_agent_alive() {  # <terminal-id> <recorded-worktree-id> [meta-path]
  case "$(fm_backend_orca_agent_snapshot "$@")" in
    working|done) printf 'alive' ;;
    no-agent) printf 'dead' ;;
    *) printf 'unknown' ;;
  esac
}

fm_backend_orca_repo_ensure() {  # <project-path>
  local project=$1 out repo_id
  fm_backend_orca_tool_check || return 1
  out=$(orca repo show --repo "path:$project" --json 2>/dev/null || true)
  if repo_id=$(printf '%s' "$out" | fm_backend_orca_json_get repo-id 2>/dev/null); then
    printf '%s' "$repo_id"
    return 0
  fi
  out=$(orca repo add --path "$project" --json) || return 1
  repo_id=$(printf '%s' "$out" | fm_backend_orca_json_get repo-id) || {
    echo "error: orca repo add did not return a repo id for $project" >&2
    return 1
  }
  printf '%s' "$repo_id"
}

fm_backend_orca_worktree_create() {  # <project-path> <name>
  local project=$1 name=$2 repo_id out wt_id wt_path terminal pane_key
  repo_id=$(fm_backend_orca_repo_ensure "$project") || return 1
  out=$(orca worktree create --repo "id:$repo_id" --name "$name" --no-parent --setup skip --json) || return 1
  wt_id=$(printf '%s' "$out" | fm_backend_orca_json_get worktree-id) || {
    echo "error: orca worktree create did not return a worktree id for $name" >&2
    return 1
  }
  terminal=$(printf '%s' "$out" | fm_backend_orca_json_get worktree-terminal-handle 2>/dev/null || true)
  if [ -n "$terminal" ]; then
    pane_key=$(printf '%s' "$out" | fm_backend_orca_json_get terminal-pane-key 2>/dev/null || true)
    fm_backend_orca_pane_key_valid "$pane_key" || pane_key=
  fi
  wt_path=$(printf '%s' "$out" | fm_backend_orca_json_get worktree-path) || {
    echo "error: orca worktree create did not return a path for $name" >&2
    [ -z "$terminal" ] || fm_backend_orca_kill "$terminal" >/dev/null 2>&1 || true
    if fm_backend_orca_remove_worktree "$wt_id" >/dev/null; then
      return 1
    fi
    if [ -n "$terminal" ]; then
      printf '%s\t\t%s' "$wt_id" "$terminal"
    else
      printf '%s\t' "$wt_id"
    fi
    return 2
  }
  printf '%s\t%s' "$wt_id" "$wt_path"
  if [ -n "$terminal" ]; then
    printf '\t%s' "$terminal"
    [ -z "$pane_key" ] || printf '\t%s' "$pane_key"
  fi
}

fm_backend_orca_terminal_create() {  # <worktree-id> <title>
  local worktree_id=$1 title=$2 out terminal pane_key
  fm_backend_orca_tool_check || return 1
  out=$(orca terminal create --worktree "id:$worktree_id" --title "$title" --json) || return 1
  terminal=$(printf '%s' "$out" | fm_backend_orca_json_get terminal-handle) || {
    echo "error: orca terminal create did not return a terminal handle for $title" >&2
    return 1
  }
  printf '%s' "$terminal"
  pane_key=$(printf '%s' "$out" | fm_backend_orca_json_get terminal-pane-key 2>/dev/null || true)
  fm_backend_orca_pane_key_valid "$pane_key" || pane_key=
  [ -z "$pane_key" ] || printf '\t%s' "$pane_key"
}

fm_backend_orca_send_text_line() {  # <terminal-id> <text> [meta-path]
  local terminal=$1 text=$2 meta=${3:-} out
  fm_backend_orca_tool_check || return 1
  out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_send_line "$text") || return 1
  printf '%s' "$out" | fm_backend_orca_json_ok
}

fm_backend_orca_send_literal() {  # <terminal-id> <text> [meta-path]
  local terminal=$1 text=$2 meta=${3:-} out
  fm_backend_orca_tool_check || return 1
  out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_send_literal "$text") || return 1
  printf '%s' "$out" | fm_backend_orca_json_ok
}

fm_backend_orca_remove_worktree() {  # <worktree-id>
  local worktree_id=${1:-}
  [ -n "$worktree_id" ] || { echo "error: missing Orca worktree id; cannot remove worktree" >&2; return 1; }
  fm_backend_orca_tool_check || return 1
  fm_backend_orca_run_json orca worktree rm --worktree "id:$worktree_id" --force --json
}

fm_backend_orca_worktree_path() {
  local worktree_id=${1:-} out path
  [ -n "$worktree_id" ] || { echo "error: missing Orca worktree id; cannot resolve worktree path" >&2; return 1; }
  fm_backend_orca_tool_check || return 1
  out=$(orca worktree show --worktree "id:$worktree_id" --json) || return 1
  path=$(printf '%s' "$out" | fm_backend_orca_json_get worktree-path) || {
    echo "error: orca worktree show did not return a path for $worktree_id" >&2
    return 1
  }
  printf '%s' "$path"
}

fm_backend_orca_capture() {  # <terminal-id> <lines> [meta-path]
  local terminal=$1 lines=${2:-40} meta=${3:-} out
  fm_backend_orca_tool_check || return 1
  out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_terminal_read --limit "$lines") || return 1
  fm_backend_orca_json_text "$out"
}

fm_backend_orca_json_text() {  # <json>
  printf '%s' "$1" | node -e '
const fs = require("fs");
const data = JSON.parse(fs.readFileSync(0, "utf8"));
if (data.ok === false) {
  const msg = data.error && (data.error.message || data.error.code);
  if (msg) console.error(msg);
  process.exit(2);
}
const r = data.result || {};
if (r.terminal && Array.isArray(r.terminal.tail)) {
  process.stdout.write(r.terminal.tail.join("\n"));
} else if (Array.isArray(r.tail)) {
  process.stdout.write(r.tail.join("\n"));
} else {
  process.stdout.write(r.text || r.output || r.content || r.preview || "");
}
'
}

fm_backend_orca_json_field() {  # <field> <json>
  local field=$1
  printf '%s' "$2" | node -e '
const fs = require("fs");
const field = process.argv[1];
const data = JSON.parse(fs.readFileSync(0, "utf8"));
if (data.ok === false) process.exit(2);
const r = data.result || {};
const term = r.terminal || {};
function scalar(v) {
  return (typeof v === "string" || typeof v === "number" || typeof v === "boolean") ? String(v) : "";
}
let v = "";
if (field === "limited") v = scalar(r.limited ?? term.limited);
if (field === "oldestCursor") v = scalar(r.oldestCursor || term.oldestCursor);
if (field === "nextCursor") v = scalar(r.nextCursor || term.nextCursor);
if (field === "latestCursor") v = scalar(r.latestCursor || term.latestCursor);
if (!v) process.exit(1);
process.stdout.write(v);
' "$field"
}

fm_backend_orca_read_text_paged() {  # <terminal-id> <limit> [meta-path]
  local terminal=$1 limit=${2:-200} meta=${3:-} out limited oldest cursor_out text older_text
  fm_backend_orca_tool_check || return 1
  out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_terminal_read --limit "$limit") || return 1
  printf '%s' "$out" | fm_backend_orca_json_ok || return 1
  text=$(fm_backend_orca_json_text "$out") || return 1
  limited=$(fm_backend_orca_json_field limited "$out" 2>/dev/null || true)
  oldest=$(fm_backend_orca_json_field oldestCursor "$out" 2>/dev/null || true)
  if [ "$limited" = true ] && [ -n "$oldest" ]; then
    cursor_out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_terminal_read --cursor "$oldest" --limit "$limit") || return 1
    printf '%s' "$cursor_out" | fm_backend_orca_json_ok || return 1
    older_text=$(fm_backend_orca_json_text "$cursor_out") || return 1
    text="${older_text}"$'\n'"${text}"
  fi
  printf '%s' "$text"
}

FM_BACKEND_ORCA_COMPOSER_LINES=${FM_BACKEND_ORCA_COMPOSER_LINES:-200}
FM_BACKEND_ORCA_IDLE_RE=${FM_BACKEND_ORCA_IDLE_RE:-'^Type a message\.\.\.$'}

# fm_backend_orca_composer_state: classify the composer's own bordered row as
# empty|pending|unknown. Real text stays pending, including a slash-command
# popup that closed by filling an argument-hint placeholder into the composer;
# that first Enter selected the popup item, it did not submit the command.
fm_backend_orca_composer_state() {  # <terminal-id> [meta-path] -> empty|pending|unknown
  local terminal=$1 meta=${2:-} cap line trimmed stripped="" found=0
  cap=$(fm_backend_orca_read_text_paged "$terminal" "$FM_BACKEND_ORCA_COMPOSER_LINES" "$meta") || { printf 'unknown'; return 0; }
  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [ -n "$trimmed" ] || continue
    case "$trimmed" in
      '│'*'│'|'┃'*'┃'|'|'*'|') : ;;
      *) continue ;;
    esac
    stripped=$trimmed
    found=1
  done < <(printf '%s\n' "$cap")
  [ "$found" -eq 1 ] || { printf 'unknown'; return 0; }
  stripped=${stripped//│/}
  stripped=${stripped//┃/}
  stripped=${stripped//|/}
  stripped="${stripped#"${stripped%%[![:space:]]*}"}"
  stripped="${stripped%"${stripped##*[![:space:]]}"}"
  # A row was found only by the bordered shape above, so content came from a
  # genuine composer box - delegate to the shared owner with bordered=1. A bare
  # dead-shell prompt has no bordered row and already returned 'unknown' above.
  fm_composer_classify_content 1 "$stripped" "$FM_BACKEND_ORCA_IDLE_RE"
}

fm_backend_orca_send_key() {  # <terminal-id> <key> [meta-path]
  local terminal=$1 key=$2 meta=${3:-} out
  fm_backend_orca_tool_check || return 1
  case "$key" in
    C-c|ctrl+c|Ctrl-c|Ctrl-C)
      out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_send_interrupt) || return 1
      ;;
    Enter|enter)
      out=$(fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_send_enter) || return 1
      ;;
    *)
      echo "error: unsupported Orca key '$key'" >&2
      return 1
      ;;
  esac
  printf '%s' "$out" | fm_backend_orca_json_ok
}

# fm_backend_orca_send_text_submit: type <text> once, then retry Enter until
# the composer row reads empty. Retries send only Enter, so a slash-command
# popup placeholder fill gets the required second Enter without duplicating text.
fm_backend_orca_send_text_submit() {  # <terminal-id> <text> <retries> <enter-sleep> <settle> [meta-path]
  local terminal=$1 text=$2 retries=$3 sleep_s=$4 settle=$5 meta=${6:-} i=0 state
  fm_backend_orca_tool_check || { printf 'send-failed'; return 0; }
  fm_backend_orca_send_literal "$terminal" "$text" "$meta" || { printf 'send-failed'; return 0; }
  sleep "$settle"
  while :; do
    fm_backend_orca_send_key "$terminal" Enter "$meta" || true
    sleep "$sleep_s"
    state=$(fm_backend_orca_composer_state "$terminal" "$meta")
    [ "$state" = pending ] || { printf '%s' "$state"; return 0; }
    i=$((i + 1))
    [ "$i" -lt "$retries" ] || { printf 'pending'; return 0; }
  done
}

fm_backend_orca_kill() {  # <terminal-id> [meta-path]
  local terminal=$1 meta=${2:-}
  fm_backend_orca_tool_check || return 0
  fm_backend_orca_with_recovery "$meta" "$terminal" fm_backend_orca_raw_close >/dev/null 2>&1 || true
}

# --- Shared-worktree team panes ----------------------------------------------
#
# A team task is an ordinary Orca ship/scout task whose meta additionally
# records plural durable teammate pane identities inside the SAME task
# worktree. This is an explicit opt-in contract created by bin/fm-team.sh,
# never something spawn or recovery infers. Contract fields (single-line,
# space-separated lists kept in recorded order):
#
#   team_edit_policy=coordinator-only   the only supported concurrent-edit
#                                       policy: the coordinator terminal owns
#                                       every file edit and git state change;
#                                       teammate panes are advisory
#   orca_team_pane_keys=<pk> [<pk>...]  durable teammate identities
#                                       (tabId:leafId), the authoritative record
#   orca_team_terminals=<h> [<h>...]    runtime-epoch handle cache, same order;
#                                       never authoritative - handles remint
#
# The coordinator's own terminal=/orca_pane_key= fields are unchanged and are
# NOT part of the team lists: the coordinator stays firstmate's single direct
# report; teammates are task-owned extra panes addressed only through
# bin/fm-team.sh.

fm_backend_orca_team_pane_keys() {  # <meta-path>
  [ -f "$1" ] || return 0
  grep '^orca_team_pane_keys=' "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

fm_backend_orca_team_terminals() {  # <meta-path>
  [ -f "$1" ] || return 0
  grep '^orca_team_terminals=' "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

fm_backend_orca_team_edit_policy() {  # <meta-path>
  [ -f "$1" ] || return 0
  grep '^team_edit_policy=' "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

fm_backend_orca_team_list_contains() {  # <space-list> <item>
  local item
  for item in $1; do
    [ "$item" = "$2" ] && return 0
  done
  return 1
}

# CAS rewrite of the three team contract lines under the meta lock. The caller
# passes the pane-key list it last read; any concurrent change (list, task
# generation, lifecycle claim) makes the whole update refuse so a teardown or a
# racing add can never be silently overwritten.
fm_backend_orca_meta_team_write() {  # <meta-path> <expected-generation> <expected-pane-keys> <new-pane-keys> <new-terminals>
  local meta=$1 expected_generation=$2 expected_keys=$3 new_keys=$4 new_terminals=$5
  local current_generation current_keys tmp status=0
  fm_meta_lock_acquire "$meta" || return 1
  if [ -f "$meta" ] && fm_meta_is_active_unlocked "$meta"; then
    current_generation=$(fm_meta_value_unlocked "$meta" generation)
    current_keys=$(grep '^orca_team_pane_keys=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    [ "$current_generation" = "$expected_generation" ] || status=1
    [ "$current_keys" = "$expected_keys" ] || status=1
  else
    status=1
  fi
  tmp="$meta.tmp.$$"
  if [ "$status" -eq 0 ]; then
    awk -v keys="$new_keys" -v terminals="$new_terminals" '
    BEGIN { wrote_policy = 0; wrote_keys = 0; wrote_terminals = 0 }
    /^team_edit_policy=/ {
      if (!wrote_policy) print "team_edit_policy=coordinator-only"
      wrote_policy = 1
      next
    }
    /^orca_team_pane_keys=/ {
      if (!wrote_keys && keys != "") print "orca_team_pane_keys=" keys
      wrote_keys = 1
      next
    }
    /^orca_team_terminals=/ {
      if (!wrote_terminals && terminals != "") print "orca_team_terminals=" terminals
      wrote_terminals = 1
      next
    }
    { print }
    END {
      if (!wrote_policy) print "team_edit_policy=coordinator-only"
      if (!wrote_keys && keys != "") print "orca_team_pane_keys=" keys
      if (!wrote_terminals && terminals != "") print "orca_team_terminals=" terminals
    }
  ' "$meta" > "$tmp" || status=$?
  fi
  if [ "$status" -eq 0 ]; then
    mv "$tmp" "$meta" || status=$?
  else
    rm -f "$tmp"
  fi
  fm_meta_lock_release "$meta"
  return "$status"
}

fm_backend_orca_meta_team_append() {  # <meta-path> <expected-generation> <expected-pane-keys> <pane-key> <terminal-handle>
  local meta=$1 expected_generation=$2 expected_keys=$3 pane_key=$4 terminal=$5 terminals new_keys new_terminals
  fm_backend_orca_pane_key_valid "$pane_key" || {
    echo "error: refusing to record invalid teammate pane key '$pane_key'" >&2
    return 1
  }
  [ -n "$terminal" ] || { echo "error: refusing to record teammate pane without a terminal handle" >&2; return 1; }
  if fm_backend_orca_team_list_contains "$expected_keys" "$pane_key"; then
    echo "error: teammate pane $pane_key is already recorded in $meta" >&2
    return 1
  fi
  terminals=$(fm_backend_orca_team_terminals "$meta")
  new_keys="${expected_keys:+$expected_keys }$pane_key"
  new_terminals="${terminals:+$terminals }$terminal"
  fm_backend_orca_meta_team_write "$meta" "$expected_generation" "$expected_keys" "$new_keys" "$new_terminals"
}

fm_backend_orca_meta_team_remove() {  # <meta-path> <expected-generation> <pane-key>
  local meta=$1 expected_generation=$2 pane_key=$3 keys terminals new_keys='' new_terminals='' key terminal i=0
  local -a terminal_arr=()
  keys=$(fm_backend_orca_team_pane_keys "$meta")
  fm_backend_orca_team_list_contains "$keys" "$pane_key" || {
    echo "error: teammate pane $pane_key is not recorded in $meta" >&2
    return 1
  }
  terminals=$(fm_backend_orca_team_terminals "$meta")
  # shellcheck disable=SC2206  # handles/pane keys never contain whitespace
  terminal_arr=($terminals)
  for key in $keys; do
    terminal=${terminal_arr[$i]:-}
    i=$((i + 1))
    [ "$key" = "$pane_key" ] && continue
    new_keys="${new_keys:+$new_keys }$key"
    [ -z "$terminal" ] || new_terminals="${new_terminals:+$new_terminals }$terminal"
  done
  fm_backend_orca_meta_team_write "$meta" "$expected_generation" "$keys" "$new_keys" "$new_terminals"
}

# fm_backend_orca_team_resolve_pane: resolve one durable pane identity inside
# one worktree to its current runtime handle, with three distinguishable
# outcomes so callers can fail closed on ambiguity:
#   exit 0  exactly one match; prints "<handle>\t<connected>\t<writable>"
#   exit 2  definitively gone: full enumeration succeeded and zero terminals
#           carry this pane key
#   exit 1  unresolved: list failure, malformed shapes, an unreadable
#           candidate, or duplicate matches - never treated as gone
# `terminal show` (not list) owns identity because list results expose
# non-joinable `pty:` placeholder tab/leaf ids (observed on Orca 1.4.141).
fm_backend_orca_team_resolve_pane() {  # <worktree-id> <pane-key>
  local worktree_id=$1 pane_key=$2 list_out handles handle show_out record candidate_worktree rest candidate_pane connected writable unresolved=0
  local -a matches=() match_meta=()
  [ -n "$worktree_id" ] || { echo "error: team pane resolution needs a worktree id" >&2; return 1; }
  fm_backend_orca_pane_key_valid "$pane_key" || { echo "error: team pane resolution needs a valid pane key, got '$pane_key'" >&2; return 1; }
  list_out=$(orca terminal list --worktree "id:$worktree_id" --json 2>/dev/null) || {
    echo "error: team pane unresolved: terminal list failed for worktree $worktree_id" >&2
    return 1
  }
  handles=$(fm_backend_orca_json_terminal_handles "$list_out" 2>/dev/null) || {
    echo "error: team pane unresolved: invalid terminal list for worktree $worktree_id" >&2
    return 1
  }
  while IFS= read -r handle; do
    [ -n "$handle" ] || continue
    show_out=$(orca terminal show --terminal "$handle" --json 2>/dev/null) || {
      echo "error: team pane unresolved: candidate $handle could not be shown" >&2
      unresolved=1
      continue
    }
    record=$(fm_backend_orca_terminal_record "$show_out" 2>/dev/null) || {
      echo "error: team pane unresolved: candidate $handle returned an invalid terminal shape" >&2
      unresolved=1
      continue
    }
    candidate_worktree=${record%%$'\t'*}
    rest=${record#*$'\t'}
    candidate_pane=${rest%%$'\t'*}
    rest=${rest#*$'\t'}
    connected=${rest%%$'\t'*}
    writable=${rest#*$'\t'}
    fm_backend_orca_pane_key_valid "$candidate_pane" || {
      echo "error: team pane unresolved: candidate $handle returned an invalid pane key" >&2
      unresolved=1
      continue
    }
    if [ "$candidate_worktree" = "$worktree_id" ] && [ "$candidate_pane" = "$pane_key" ]; then
      matches+=("$handle")
      match_meta+=("$connected"$'\t'"$writable")
    fi
  done <<< "$handles"
  [ "$unresolved" -eq 0 ] || return 1
  case "${#matches[@]}" in
    0) return 2 ;;
    1) printf '%s\t%s' "${matches[0]}" "${match_meta[0]}" ;;
    *)
      echo "error: team pane ambiguous: pane $pane_key matches multiple terminals: ${matches[*]}" >&2
      return 1
      ;;
  esac
}

# fm_backend_orca_team_pane_state: per-pane inventory read for one recorded
# teammate. Every value is a directly observable CLI fact, never a guess:
#   working   the pane's exact paneKey appears in the exact worktree's
#             well-formed agents[] with state "working"
#   done      same join with state "done" (turn complete, agent still open)
#   no-agent  the pane is connected and writable but its exact paneKey is
#             absent from the worktree's well-formed agents[] inventory -
#             a plain shell or an exited agent occupies the pane
#   gone      no terminal in the worktree carries this pane key (clean
#             enumeration; the pane was closed)
#   unknown   anything else - resolution ambiguity, malformed inventory,
#             disconnected/non-writable pane, duplicate identities
# This is deliberately a separate reader from the coordinator's
# fm_backend_orca_agent_snapshot: the coordinator's accepted E1b liveness
# contract (empty agents[] => dead) is unchanged.
fm_backend_orca_team_pane_state() {  # <worktree-id> <pane-key>
  local worktree_id=${1:-} pane_key=${2:-} resolved rc handle rest connected writable ps_out state
  [ -n "$worktree_id" ] && [ -n "$pane_key" ] || { printf 'unknown'; return 0; }
  fm_backend_orca_tool_check >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  if resolved=$(fm_backend_orca_team_resolve_pane "$worktree_id" "$pane_key" 2>/dev/null); then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 2 ]; then
    printf 'gone'
    return 0
  fi
  [ "$rc" -eq 0 ] || { printf 'unknown'; return 0; }
  handle=${resolved%%$'\t'*}
  rest=${resolved#*$'\t'}
  connected=${rest%%$'\t'*}
  writable=${rest#*$'\t'}
  : "$handle"
  { [ "$connected" = true ] && [ "$writable" = true ]; } || { printf 'unknown'; return 0; }
  ps_out=$(orca worktree ps --json 2>/dev/null) || { printf 'unknown'; return 0; }
  state=$(printf '%s' "$ps_out" | node -e '
const fs = require("fs");
const worktreeId = process.argv[1];
const paneKey = process.argv[2];
let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (_) {
  process.exit(1);
}
if (data.ok !== true || !data.result || !Array.isArray(data.result.worktrees)) process.exit(1);
const worktrees = data.result.worktrees.filter((worktree) => worktree && worktree.worktreeId === worktreeId);
if (worktrees.length !== 1 || !Array.isArray(worktrees[0].agents)) process.exit(1);
if (!worktrees[0].agents.every((agent) => agent && typeof agent === "object" && typeof agent.paneKey === "string" && agent.paneKey.length > 0 && typeof agent.state === "string" && agent.state.length > 0)) process.exit(1);
const agents = worktrees[0].agents.filter((agent) => agent.paneKey === paneKey);
if (agents.length === 0) {
  process.stdout.write("no-agent");
  process.exit(0);
}
if (agents.length !== 1) process.exit(1);
const state = agents[0].state;
if (state !== "working" && state !== "done") process.exit(1);
process.stdout.write(state);
' "$worktree_id" "$pane_key" 2>/dev/null) || { printf 'unknown'; return 0; }
  case "$state" in
    working|done|no-agent) printf '%s' "$state" ;;
    *) printf 'unknown' ;;
  esac
}
