#!/usr/bin/env bash
# tests/fm-team-orca.test.sh - fake-Orca-CLI tests for the shared-worktree team
# foundation: team meta contract CAS writes, fail-closed pane resolution and
# per-pane inventory state in bin/backends/orca.sh, the bin/fm-team.sh
# lifecycle, and fm-teardown.sh's enumerate-and-close-before-worktree-removal
# guarantee. All JSON fixtures use the exact shapes observed live against Orca
# app 1.4.141 (terminal create/list/show/close, worktree ps, and the
# terminal_handle_stale error), including the non-joinable `pty:` placeholder
# tab/leaf ids that terminal list exposes.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-team-orca-tests)

WTID='69c04545-e3dd-467f-9b35-0eb698cc41a7::/scratch/fm-team-task'
COORD_PANE='11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222'
MATE_PANE='92a4c804-0327-4ae6-b8a2-827cb60794c5:e42285ec-72e0-42df-b04a-038e4c84b231'
MATE2_PANE='6d34d759-95c6-4ecc-8c25-3eb6223b9e23:7d4d7c59-b905-4b1c-8ebe-10225f653d46'

make_orca_fakebin() {  # <dir> -> echoes fakebin dir
  local fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/orca" <<'SH'
#!/usr/bin/env bash
set -u
LOG="${FM_ORCA_LOG:?}"
RESP="${FM_ORCA_RESPONSES:?}"
COUNT_FILE="$RESP/.count"
next=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
{
  printf 'orca'
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >> "$LOG"
if [ "${1:-}" = status ] && [ "${FM_ORCA_STATUS_RESPONSE:-ready}" != sequence ]; then
  printf '{"ok":true,"result":{"runtime":{"reachable":true,"state":"ready"}}}\n'
  exit 0
fi
n=$next
echo "$n" > "$COUNT_FILE"
if [ -f "$RESP/$n.exit" ]; then
  exit "$(cat "$RESP/$n.exit")"
fi
[ -f "$RESP/$n.out" ] && cat "$RESP/$n.out"
exit 0
SH
  chmod +x "$fb/orca"
  printf '%s\n' "$fb"
}

orca_case() {  # <name> -> sets CASE_DIR LOG RESP FB
  CASE_DIR="$TMP_ROOT/$1"
  mkdir -p "$CASE_DIR/responses"
  LOG="$CASE_DIR/log"
  RESP="$CASE_DIR/responses"
  : > "$LOG"
  FB=$(make_orca_fakebin "$CASE_DIR")
}

neutral_fm_root() {  # <dir> -> echoes a minimal root with a quiet guard
  local root="$1/root"
  mkdir -p "$root/bin"
  cat > "$root/bin/fm-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$root/bin/fm-guard.sh"
  printf '%s\n' "$root"
}

# Exact observed 1.4.141 shapes -----------------------------------------------

list_json() {  # <handle:paneish> ... -> terminal list result with pty: placeholder tab/leaf ids
  local entries='' handle
  for handle in "$@"; do
    [ -z "$entries" ] || entries="$entries,"
    entries="$entries{\"handle\":\"$handle\",\"ptyId\":\"$WTID@@c2fc5da5\",\"worktreeId\":\"$WTID\",\"worktreePath\":\"/scratch/fm-team-task\",\"branch\":\"refs/heads/fm/team-task\",\"tabId\":\"pty:$WTID@@c2fc5da5\",\"leafId\":\"pty:$WTID@@c2fc5da5\",\"title\":\"fm-team\",\"connected\":true,\"writable\":true,\"lastOutputAt\":1784119087114,\"preview\":\"\$\"}"
  done
  printf '{"id":"dcacf480-6494-4684-9062-510d761fd117","ok":true,"result":{"terminals":[%s],"totalCount":%s,"truncated":false},"_meta":{"runtimeId":"0bd01591-5ed4-48c5-99d4-94a9ad338ca6"}}\n' "$entries" "$#"
}

show_json() {  # <handle> <pane-key> <connected> <writable> [worktree-id]
  local handle=$1 pane=$2 connected=$3 writable=$4 wt=${5:-$WTID} tab leaf
  tab=${pane%%:*}
  leaf=${pane#*:}
  printf '{"id":"17bdd106-b940-4a57-8ca1-5ce89158598c","ok":true,"result":{"terminal":{"handle":"%s","ptyId":"%s@@2485e01d","worktreeId":"%s","worktreePath":"/scratch/fm-team-task","branch":"refs/heads/fm/team-task","tabId":"%s","leafId":"%s","title":"fm-team","connected":%s,"writable":%s,"lastOutputAt":1784119503460,"preview":"$","paneRuntimeId":-1,"rendererGraphEpoch":0}},"_meta":{"runtimeId":"0bd01591-5ed4-48c5-99d4-94a9ad338ca6"}}\n' \
    "$handle" "$wt" "$wt" "$tab" "$leaf" "$connected" "$writable"
}

create_json() {  # <handle> <pane-key> <title>
  local handle=$1 pane=$2 title=$3 tab
  tab=${pane%%:*}
  printf '{"id":"e68c91d7-78b5-444f-9f8d-67bb2f34b70c","ok":true,"result":{"terminal":{"handle":"%s","tabId":"%s","paneKey":"%s","ptyId":"%s@@dd9e153b","worktreeId":"%s","title":"%s","surface":"visible"}},"_meta":{"runtimeId":"0bd01591-5ed4-48c5-99d4-94a9ad338ca6"}}\n' \
    "$handle" "$tab" "$pane" "$WTID" "$WTID" "$title"
}

ps_json() {  # <agents-json-array> [worktree-id]
  printf '{"id":"6bd5b84a-0619-4d1d-be92-a949f2395b2a","ok":true,"result":{"worktrees":[{"workspaceKind":"git","worktreeId":"%s","repoId":"69c04545-e3dd-467f-9b35-0eb698cc41a7","path":"/scratch/fm-team-task","liveTerminalCount":2,"status":"active","agents":%s}]},"_meta":{"runtimeId":"0bd01591-5ed4-48c5-99d4-94a9ad338ca6"}}\n' \
    "${2:-$WTID}" "$1"
}

agent_json() {  # <pane-key> <state>
  printf '{"paneKey":"%s","parentPaneKey":null,"state":"%s","agentType":"claude","prompt":"work","taskTitle":null,"displayName":null,"lastAssistantMessage":"..."}' "$1" "$2"
}

stale_json() {
  printf '{"id":"82527dff-2367-436c-bd08-dd033a1285a6","ok":false,"error":{"code":"terminal_handle_stale","message":"terminal_handle_stale"},"_meta":{"runtimeId":"0bd01591-5ed4-48c5-99d4-94a9ad338ca6"}}\n'
}

write_team_meta() {  # <meta> <generation> [extra lines...]
  local meta=$1 generation=$2
  shift 2
  fm_write_meta "$meta" \
    "window=fm-team-task" "generation=$generation" "terminal=term_coord" \
    "worktree=/scratch/fm-team-task" "project=/scratch/project" \
    "harness=claude" "kind=ship" "mode=no-mistakes" "yolo=off" \
    "backend=orca" "orca_worktree_id=$WTID" "orca_pane_key=$COORD_PANE" "$@"
}

# --- meta contract CAS -------------------------------------------------------

test_meta_team_append_records_contract() {
  local dir meta out
  dir="$TMP_ROOT/append-contract"
  mkdir -p "$dir"
  meta="$dir/task.meta"
  write_team_meta "$meta" gen-1
  out=$( bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-1 "" "$2" term_mate_1' "$ROOT" "$meta" "$MATE_PANE" 2>&1 ) \
    || fail "first teammate append should succeed: $out"
  assert_grep 'team_edit_policy=coordinator-only' "$meta" "append did not record the coordinator-only edit policy"
  assert_grep "orca_team_pane_keys=$MATE_PANE" "$meta" "append did not record the teammate pane key"
  assert_grep 'orca_team_terminals=term_mate_1' "$meta" "append did not record the teammate handle cache"
  out=$( bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-1 "$2" "$3" term_mate_2' "$ROOT" "$meta" "$MATE_PANE" "$MATE2_PANE" 2>&1 ) \
    || fail "second teammate append should succeed: $out"
  assert_grep "orca_team_pane_keys=$MATE_PANE $MATE2_PANE" "$meta" "second append did not extend the pane-key list in order"
  assert_grep 'orca_team_terminals=term_mate_1 term_mate_2' "$meta" "second append did not extend the handle cache in order"
  pass "fm_backend_orca_meta_team_append: records policy plus ordered plural pane identities"
}

test_meta_team_append_cas_refuses_stale_or_invalid() {
  local dir meta status
  dir="$TMP_ROOT/append-cas"
  mkdir -p "$dir"
  meta="$dir/task.meta"
  write_team_meta "$meta" gen-1 "orca_team_pane_keys=$MATE_PANE" "orca_team_terminals=term_mate_1"
  set +e
  bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-OTHER "$2" "$3" term_x' "$ROOT" "$meta" "$MATE_PANE" "$MATE2_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "append must refuse a generation mismatch"
  set +e
  bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-1 "" "$2" term_x' "$ROOT" "$meta" "$MATE2_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "append must refuse a stale expected pane-key list"
  set +e
  bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-1 "$2" "$2" term_x' "$ROOT" "$meta" "$MATE_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "append must refuse a duplicate pane key"
  set +e
  bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-1 "$2" not-a-pane-key term_x' "$ROOT" "$meta" "$MATE_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "append must refuse an invalid pane key"
  assert_grep "orca_team_pane_keys=$MATE_PANE" "$meta" "refused appends must leave the recorded list unchanged"
  assert_no_grep "$MATE2_PANE" "$meta" "refused appends must not record the new pane key"
  printf 'lifecycle=teardown:tok:1:stamp\n' >> "$meta"
  set +e
  bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_append "$1" gen-1 "$2" "$3" term_x' "$ROOT" "$meta" "$MATE_PANE" "$MATE2_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "append must refuse while a teardown lifecycle claim is recorded"
  pass "fm_backend_orca_meta_team_append: CAS refuses stale, duplicate, invalid, and claimed metadata"
}

test_meta_team_remove_drops_matching_pair() {
  local dir meta out
  dir="$TMP_ROOT/remove-pair"
  mkdir -p "$dir"
  meta="$dir/task.meta"
  write_team_meta "$meta" gen-1 \
    "team_edit_policy=coordinator-only" \
    "orca_team_pane_keys=$MATE_PANE $MATE2_PANE" \
    "orca_team_terminals=term_mate_1 term_mate_2"
  out=$( bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_meta_team_remove "$1" gen-1 "$2"' "$ROOT" "$meta" "$MATE_PANE" 2>&1 ) \
    || fail "remove should succeed for a recorded pane: $out"
  assert_grep "orca_team_pane_keys=$MATE2_PANE" "$meta" "remove did not keep the other pane key"
  assert_grep 'orca_team_terminals=term_mate_2' "$meta" "remove did not drop the paired handle"
  assert_no_grep "$MATE_PANE" "$meta" "remove must drop the removed pane key"
  assert_no_grep 'term_mate_1' "$meta" "remove must drop the removed pane's handle"
  pass "fm_backend_orca_meta_team_remove: drops exactly the matching key/handle pair"
}

test_meta_identity_covers_team_contract() {
  local dir meta out
  dir="$TMP_ROOT/identity"
  mkdir -p "$dir"
  meta="$dir/task.meta"
  write_team_meta "$meta" gen-1 \
    "team_edit_policy=coordinator-only" "orca_team_pane_keys=$MATE_PANE"
  out=$( bash -c '. "$0/bin/fm-meta-lib.sh"; fm_meta_identity_unlocked "$1"' "$ROOT" "$meta" )
  assert_contains "$out" "orca_team_pane_keys=$MATE_PANE" "task identity must cover the plural pane identities"
  assert_contains "$out" 'team_edit_policy=coordinator-only' "task identity must cover the edit-policy contract"
  pass "fm_meta_identity_unlocked: team contract fields are identity-bearing"
}

# --- pane resolution ----------------------------------------------------------

test_team_resolve_pane_exact_match() {
  local out
  orca_case resolve-exact
  list_json term_coord term_mate_1 > "$RESP/1.out"
  show_json term_coord "$COORD_PANE" true true > "$RESP/2.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/3.out"
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_team_resolve_pane "$1" "$2"' "$ROOT" "$WTID" "$MATE_PANE" )
  [ "$out" = "term_mate_1"$'\t'"true"$'\t'"true" ] || fail "resolve should print handle/connected/writable, got '$out'"
  assert_contains "$(cat "$LOG")" $'orca\x1f''terminal'$'\x1f''list'$'\x1f''--worktree'$'\x1f'"id:$WTID" \
    "resolution must enumerate through worktree-scoped terminal list"
  pass "fm_backend_orca_team_resolve_pane: exact unique pane-key match resolves through show"
}

test_team_resolve_pane_gone_after_clean_enumeration() {
  local status
  orca_case resolve-gone
  list_json term_coord > "$RESP/1.out"
  show_json term_coord "$COORD_PANE" true true > "$RESP/2.out"
  set +e
  PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_team_resolve_pane "$1" "$2"' "$ROOT" "$WTID" "$MATE_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -eq 2 ] || fail "clean enumeration with zero matches must exit 2 (gone), got $status"
  pass "fm_backend_orca_team_resolve_pane: zero matches after clean enumeration is definitively gone"
}

test_team_resolve_pane_unreadable_candidate_is_unresolved() {
  local status
  orca_case resolve-unreadable
  list_json term_coord term_mate_1 > "$RESP/1.out"
  stale_json > "$RESP/2.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/3.out"
  set +e
  PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_team_resolve_pane "$1" "$2"' "$ROOT" "$WTID" "$MATE_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -eq 1 ] || fail "an unreadable candidate must make the attempt unresolved (exit 1), got $status"
  pass "fm_backend_orca_team_resolve_pane: unreadable candidate fails closed even when another matches"
}

test_team_resolve_pane_duplicates_are_unresolved() {
  local status
  orca_case resolve-duplicates
  list_json term_a term_b > "$RESP/1.out"
  show_json term_a "$MATE_PANE" true true > "$RESP/2.out"
  show_json term_b "$MATE_PANE" true true > "$RESP/3.out"
  set +e
  PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_team_resolve_pane "$1" "$2"' "$ROOT" "$WTID" "$MATE_PANE" 2>/dev/null
  status=$?
  set -e
  [ "$status" -eq 1 ] || fail "duplicate pane-key matches must be unresolved (exit 1), got $status"
  pass "fm_backend_orca_team_resolve_pane: duplicate identities fail closed"
}

# --- per-pane inventory state --------------------------------------------------

team_pane_state() {  # -> echoes state; uses current case fixtures
  PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    bash -c '. "$0/bin/backends/orca.sh"; fm_backend_orca_team_pane_state "$1" "$2"' "$ROOT" "$WTID" "$MATE_PANE"
}

test_team_pane_state_working_and_done() {
  local out
  orca_case pane-state-working
  list_json term_mate_1 > "$RESP/1.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/2.out"
  ps_json "[$(agent_json "$COORD_PANE" working),$(agent_json "$MATE_PANE" working)]" > "$RESP/3.out"
  out=$(team_pane_state)
  [ "$out" = working ] || fail "matched agent working should be working, got '$out'"
  orca_case pane-state-done
  list_json term_mate_1 > "$RESP/1.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/2.out"
  ps_json "[$(agent_json "$COORD_PANE" working),$(agent_json "$MATE_PANE" 'done')]" > "$RESP/3.out"
  out=$(team_pane_state)
  [ "$out" = 'done' ] || fail "matched agent done should be done, got '$out'"
  pass "fm_backend_orca_team_pane_state: exact pane-key joins map working/done"
}

test_team_pane_state_no_agent_and_gone() {
  local out
  orca_case pane-state-no-agent
  list_json term_mate_1 > "$RESP/1.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/2.out"
  ps_json "[$(agent_json "$COORD_PANE" working)]" > "$RESP/3.out"
  out=$(team_pane_state)
  [ "$out" = no-agent ] || fail "connected writable pane absent from agents[] should be no-agent, got '$out'"
  orca_case pane-state-gone
  list_json term_coord > "$RESP/1.out"
  show_json term_coord "$COORD_PANE" true true > "$RESP/2.out"
  out=$(team_pane_state)
  [ "$out" = gone ] || fail "cleanly enumerated missing pane should be gone, got '$out'"
  pass "fm_backend_orca_team_pane_state: no-agent needs a live pane; gone needs clean enumeration"
}

test_team_pane_state_fails_closed_to_unknown() {
  local out
  orca_case pane-state-disconnected
  list_json term_mate_1 > "$RESP/1.out"
  show_json term_mate_1 "$MATE_PANE" false true > "$RESP/2.out"
  out=$(team_pane_state)
  [ "$out" = unknown ] || fail "disconnected pane should be unknown, got '$out'"
  orca_case pane-state-malformed-ps
  list_json term_mate_1 > "$RESP/1.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/2.out"
  printf 'not json\n' > "$RESP/3.out"
  out=$(team_pane_state)
  [ "$out" = unknown ] || fail "malformed worktree ps should be unknown, got '$out'"
  orca_case pane-state-list-failed
  printf '1\n' > "$RESP/1.exit"
  out=$(team_pane_state)
  [ "$out" = unknown ] || fail "list failure should be unknown, got '$out'"
  pass "fm_backend_orca_team_pane_state: ambiguity and malformed inventory stay unknown"
}

# --- fm-team.sh ---------------------------------------------------------------

test_fm_team_add_records_verified_pane() {
  local state out rc
  orca_case team-add
  state="$CASE_DIR/state"
  mkdir -p "$state"
  touch "$state/.last-watcher-beat"
  write_team_meta "$state/team-task.meta" gen-1
  create_json term_mate_1 "$MATE_PANE" fm-team-task-mate-1 > "$RESP/1.out"
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$state" \
    "$ROOT/bin/fm-team.sh" add team-task 2>&1 )
  rc=$?
  set -e
  expect_code 0 "$rc" "fm-team.sh add should succeed on the verified creation shape"$'\n'"$out"
  assert_grep "orca_team_pane_keys=$MATE_PANE" "$state/team-task.meta" "add did not record the teammate pane key"
  assert_grep 'orca_team_terminals=term_mate_1' "$state/team-task.meta" "add did not record the teammate handle"
  assert_grep 'team_edit_policy=coordinator-only' "$state/team-task.meta" "add did not record the edit policy"
  assert_contains "$(cat "$LOG")" $'orca\x1f''terminal'$'\x1f''create'$'\x1f''--worktree'$'\x1f'"id:$WTID"$'\x1f''--title'$'\x1f''fm-team-task-mate-1' \
    "add did not create the titled teammate terminal in the recorded worktree"
  pass "fm-team.sh add: verified creation shape becomes a recorded plural identity"
}

test_fm_team_add_closes_pane_without_durable_identity() {
  local state out rc
  orca_case team-add-no-panekey
  state="$CASE_DIR/state"
  mkdir -p "$state"
  touch "$state/.last-watcher-beat"
  write_team_meta "$state/team-task.meta" gen-1
  printf '{"ok":true,"result":{"terminal":{"handle":"term_mate_1","worktreeId":"%s","title":"t","surface":"visible"}}}\n' "$WTID" > "$RESP/1.out"
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$state" \
    "$ROOT/bin/fm-team.sh" add team-task 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "add must refuse a creation without a durable pane key"
  assert_contains "$out" "did not return a valid pane key" "refusal should explain the missing durable identity"
  assert_contains "$(cat "$LOG")" $'orca\x1f''terminal'$'\x1f''close'$'\x1f''--terminal'$'\x1f''term_mate_1' \
    "the unaddressable pane must be closed, not leaked"
  assert_no_grep 'orca_team_pane_keys=' "$state/team-task.meta" "no teammate may be recorded without a pane key"
  pass "fm-team.sh add: creation without a pane key is closed and refused"
}

test_fm_team_add_refuses_non_orca_and_claimed_meta() {
  local state out rc
  orca_case team-add-refusals
  state="$CASE_DIR/state"
  mkdir -p "$state"
  touch "$state/.last-watcher-beat"
  fm_write_meta "$state/tmux-task.meta" "window=fm-tmux-task" "generation=gen-1" "kind=ship"
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" FM_STATE_OVERRIDE="$state" \
    FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-team.sh" add tmux-task 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "add must refuse a non-orca task"
  assert_contains "$out" "only supported on backend=orca" "refusal should name the backend boundary"
  write_team_meta "$state/claimed-task.meta" gen-1 "lifecycle=teardown:tok:1:stamp"
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" FM_STATE_OVERRIDE="$state" \
    FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-team.sh" add claimed-task 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "add must refuse a lifecycle-claimed task"
  assert_contains "$out" "lifecycle claim" "refusal should name the teardown claim"
  assert_not_contains "$(cat "$LOG")" $'orca\x1f''terminal'$'\x1f''create' "refused adds must not create terminals"
  pass "fm-team.sh add: non-orca and teardown-claimed tasks are refused before any Orca mutation"
}

test_fm_team_close_verifies_gone_then_removes_record() {
  local state out rc
  orca_case team-close
  state="$CASE_DIR/state"
  mkdir -p "$state"
  touch "$state/.last-watcher-beat"
  write_team_meta "$state/team-task.meta" gen-1 \
    "team_edit_policy=coordinator-only" \
    "orca_team_pane_keys=$MATE_PANE" "orca_team_terminals=term_mate_1"
  list_json term_mate_1 > "$RESP/1.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/2.out"
  : > "$RESP/3.out"  # close
  list_json term_coord > "$RESP/4.out"
  show_json term_coord "$COORD_PANE" true true > "$RESP/5.out"
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" FM_STATE_OVERRIDE="$state" \
    FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-team.sh" close team-task "$MATE_PANE" 2>&1 )
  rc=$?
  set -e
  expect_code 0 "$rc" "close should succeed once the pane is proven gone"$'\n'"$out"
  assert_contains "$(cat "$LOG")" $'orca\x1f''terminal'$'\x1f''close'$'\x1f''--terminal'$'\x1f''term_mate_1' \
    "close did not close the resolved teammate terminal"
  assert_no_grep "orca_team_pane_keys=$MATE_PANE" "$state/team-task.meta" "close did not remove the pane record"
  pass "fm-team.sh close: closes, re-verifies gone, then removes the record"
}

test_fm_team_close_keeps_record_on_ambiguity() {
  local state out rc
  orca_case team-close-ambiguous
  state="$CASE_DIR/state"
  mkdir -p "$state"
  touch "$state/.last-watcher-beat"
  write_team_meta "$state/team-task.meta" gen-1 \
    "orca_team_pane_keys=$MATE_PANE" "orca_team_terminals=term_mate_1"
  printf '1\n' > "$RESP/1.exit"
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" FM_STATE_OVERRIDE="$state" \
    FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-team.sh" close team-task "$MATE_PANE" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "close must refuse when the pane cannot be resolved"
  assert_contains "$out" "unresolved" "refusal should say the pane is unresolved"
  assert_grep "orca_team_pane_keys=$MATE_PANE" "$state/team-task.meta" "an unresolved pane must stay recorded"
  pass "fm-team.sh close: ambiguity keeps the durable record"
}

# --- teardown ------------------------------------------------------------------

test_teardown_closes_team_panes_before_worktree_removal() {
  local proj wt data state config id out rc neutral log_content close_line rm_line
  id="teamteardownz1"
  proj="$TMP_ROOT/team-teardown-project"
  wt="$TMP_ROOT/team-teardown-wt"
  data="$TMP_ROOT/team-teardown-data"
  state="$TMP_ROOT/team-teardown-state"
  config="$TMP_ROOT/team-teardown-config"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  mkdir -p "$data/$id" "$state" "$config"
  printf 'report\n' > "$data/$id/report.md"
  touch "$state/.last-watcher-beat"
  fm_write_meta "$state/$id.meta" \
    "window=fm-$id" "generation=gen-1" "terminal=term_coord" "worktree=$wt" "project=$proj" \
    "harness=claude" "kind=scout" "mode=no-mistakes" "yolo=off" \
    "backend=orca" "orca_worktree_id=$WTID" "orca_pane_key=$COORD_PANE" \
    "team_edit_policy=coordinator-only" \
    "orca_team_pane_keys=$MATE_PANE" "orca_team_terminals=term_mate_1"
  orca_case team-teardown
  printf '{"ok":true,"result":{"worktree":{"id":"%s","path":"%s"}}}\n' "$WTID" "$wt" > "$RESP/1.out"
  list_json term_mate_1 > "$RESP/2.out"
  show_json term_mate_1 "$MATE_PANE" true true > "$RESP/3.out"
  : > "$RESP/4.out"  # teammate close
  printf '{"ok":true,"result":{"terminals":[],"totalCount":0,"truncated":false}}\n' > "$RESP/5.out"
  neutral=$(neutral_fm_root "$CASE_DIR/neutral")
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    FM_ROOT_OVERRIDE="$neutral" FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    "$ROOT/bin/fm-teardown.sh" "$id" 2>&1 )
  rc=$?
  set -e
  expect_code 0 "$rc" "team teardown should succeed when every pane is proven closed"$'\n'"$out"
  log_content=$(cat "$LOG")
  assert_contains "$log_content" $'orca\x1f''terminal'$'\x1f''close'$'\x1f''--terminal'$'\x1f''term_mate_1' \
    "teardown did not close the recorded teammate pane"
  assert_contains "$log_content" $'orca\x1f''terminal'$'\x1f''close'$'\x1f''--terminal'$'\x1f''term_coord' \
    "teardown did not close the coordinator terminal"
  assert_contains "$log_content" $'orca\x1f''worktree'$'\x1f''rm'$'\x1f''--worktree'$'\x1f'"id:$WTID" \
    "teardown did not remove the Orca worktree"
  close_line=$(grep -n $'terminal\x1f''close'$'\x1f''--terminal'$'\x1f''term_mate_1' "$LOG" | head -1 | cut -d: -f1)
  rm_line=$(grep -n $'worktree\x1f''rm' "$LOG" | head -1 | cut -d: -f1)
  [ -n "$close_line" ] && [ -n "$rm_line" ] && [ "$close_line" -lt "$rm_line" ] \
    || fail "teammate pane close must happen before worktree removal (close at ${close_line:-none}, rm at ${rm_line:-none})"
  assert_absent "$state/$id.meta" "teardown should remove task metadata after full pane cleanup"
  pass "fm-teardown.sh: enumerates and closes every recorded team pane before Orca worktree removal"
}

test_teardown_refuses_unprovable_team_pane() {
  local proj wt data state config id out rc neutral
  id="teamteardownz2"
  proj="$TMP_ROOT/team-refuse-project"
  wt="$TMP_ROOT/team-refuse-wt"
  data="$TMP_ROOT/team-refuse-data"
  state="$TMP_ROOT/team-refuse-state"
  config="$TMP_ROOT/team-refuse-config"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  mkdir -p "$data/$id" "$state" "$config"
  printf 'report\n' > "$data/$id/report.md"
  touch "$state/.last-watcher-beat"
  fm_write_meta "$state/$id.meta" \
    "window=fm-$id" "generation=gen-1" "terminal=term_coord" "worktree=$wt" "project=$proj" \
    "harness=claude" "kind=scout" "mode=no-mistakes" "yolo=off" \
    "backend=orca" "orca_worktree_id=$WTID" "orca_pane_key=$COORD_PANE" \
    "orca_team_pane_keys=$MATE_PANE" "orca_team_terminals=term_mate_1"
  orca_case team-teardown-refuse
  printf '{"ok":true,"result":{"worktree":{"id":"%s","path":"%s"}}}\n' "$WTID" "$wt" > "$RESP/1.out"
  printf '1\n' > "$RESP/2.exit"  # terminal list fails: pane state unprovable
  neutral=$(neutral_fm_root "$CASE_DIR/neutral")
  set +e
  out=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
    FM_ROOT_OVERRIDE="$neutral" FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    "$ROOT/bin/fm-teardown.sh" "$id" 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "teardown must refuse when a recorded team pane cannot be proven closed"
  assert_contains "$out" "REFUSED: teammate pane $MATE_PANE" "refusal should name the unprovable pane"
  assert_not_contains "$(cat "$LOG")" $'orca\x1f''worktree'$'\x1f''rm' "no worktree removal may happen after a pane refusal"
  [ -f "$state/$id.meta" ] || fail "refused teardown must preserve task metadata"
  pass "fm-teardown.sh: an unprovable team pane refuses worktree removal and preserves metadata"
}

test_meta_team_append_records_contract
test_meta_team_append_cas_refuses_stale_or_invalid
test_meta_team_remove_drops_matching_pair
test_meta_identity_covers_team_contract
test_team_resolve_pane_exact_match
test_team_resolve_pane_gone_after_clean_enumeration
test_team_resolve_pane_unreadable_candidate_is_unresolved
test_team_resolve_pane_duplicates_are_unresolved
test_team_pane_state_working_and_done
test_team_pane_state_no_agent_and_gone
test_team_pane_state_fails_closed_to_unknown
test_fm_team_add_records_verified_pane
test_fm_team_add_closes_pane_without_durable_identity
test_fm_team_add_refuses_non_orca_and_claimed_meta
test_fm_team_close_verifies_gone_then_removes_record
test_fm_team_close_keeps_record_on_ambiguity
test_teardown_closes_team_panes_before_worktree_removal
test_teardown_refuses_unprovable_team_pane

echo "fm-team-orca tests passed"
