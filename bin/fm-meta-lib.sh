#!/usr/bin/env bash

FM_META_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fm_meta_lock_load() {
  type fm_lock_acquire_wait >/dev/null 2>&1 && return 0
  # shellcheck source=bin/fm-wake-lib.sh
  . "$FM_META_LIB_DIR/fm-wake-lib.sh"
}

fm_meta_lock_acquire() {  # <meta-path>
  [ -d "$(dirname "$1")" ] || return 1
  fm_meta_lock_load || return 1
  fm_lock_acquire_wait "$1.lock"
}

fm_meta_lock_release() {  # <meta-path>
  fm_lock_release "$1.lock"
}

fm_meta_identity_unlocked() {  # <meta-path>
  local meta=$1 key value
  [ -f "$meta" ] || return 1
  for key in generation kind window worktree project backend terminal orca_worktree_id orca_pane_key orca_team_pane_keys team_edit_policy home lifecycle; do
    value=$(grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    printf '%s=%s\n' "$key" "$value"
  done
}

fm_meta_value_unlocked() {  # <meta-path> <key>
  [ -f "$1" ] || return 1
  grep "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

fm_meta_is_active_unlocked() {  # <meta-path>
  local lifecycle
  lifecycle=$(fm_meta_value_unlocked "$1" lifecycle) || return 1
  [ -z "$lifecycle" ]
}

fm_meta_new_generation() {
  local value
  if command -v uuidgen >/dev/null 2>&1; then
    if value=$(uuidgen 2>/dev/null); then
      value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
      if printf '%s\n' "$value" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
        printf '%s\n' "$value"
        return 0
      fi
    fi
  fi
  value=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || return 1
  printf '%s\n' "$value" | grep -Eq '^[0-9a-f]{32}$' || return 1
  printf '%s\n' "$value"
}

fm_meta_process_stamp() {  # <pid>
  local stamp
  stamp=$(ps -p "$1" -o lstart= 2>/dev/null | tr -cd '[:alnum:]') || return 1
  [ -n "$stamp" ] || return 1
  printf '%s' "$stamp"
}

fm_meta_teardown_owner() {  # [token]
  local token=${1:-} stamp
  [ -n "$token" ] || token=$(fm_meta_new_generation) || return 1
  stamp=$(fm_meta_process_stamp "$$") || return 1
  printf '%s:%s:%s' "$token" "$$" "$stamp"
}

fm_meta_teardown_owner_live() {  # <owner>
  local owner=$1 rest pid expected_stamp current_stamp
  rest=${owner#*:}
  [ "$rest" != "$owner" ] || return 0
  pid=${rest%%:*}
  expected_stamp=${rest#*:}
  [ "$expected_stamp" != "$rest" ] || return 0
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  [ -n "$expected_stamp" ] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    current_stamp=$(fm_meta_process_stamp "$pid" 2>/dev/null || true)
    [ -z "$current_stamp" ] && return 0
    [ "$current_stamp" = "$expected_stamp" ]
    return
  fi
  return 1
}

fm_meta_ensure_generation() {  # <meta-path>
  local meta=$1 generation tmp status=0
  fm_meta_lock_acquire "$meta" || return 1
  if [ ! -f "$meta" ] || ! fm_meta_is_active_unlocked "$meta"; then
    status=1
  else
    generation=$(fm_meta_value_unlocked "$meta" generation)
    if [ -z "$generation" ]; then
      generation=$(fm_meta_new_generation) || status=$?
      tmp="$meta.tmp.$$"
      if [ "$status" -eq 0 ]; then
        { printf 'generation=%s\n' "$generation"; cat "$meta"; } > "$tmp" || status=$?
      fi
      if [ "$status" -eq 0 ]; then
        mv "$tmp" "$meta" || status=$?
      else
        rm -f "$tmp"
      fi
    fi
  fi
  fm_meta_lock_release "$meta"
  [ "$status" -eq 0 ] || return "$status"
  printf '%s' "$generation"
}

fm_meta_claim_teardown() {  # <meta-path> <expected-identity> <owner> [resume-token]
  local meta=$1 expected=$2 owner=$3 resume_token=${4:-} current lifecycle existing_owner existing_token tmp claimed status=0
  fm_meta_lock_acquire "$meta" || return 1
  current=$(fm_meta_identity_unlocked "$meta") || status=$?
  lifecycle=$(fm_meta_value_unlocked "$meta" lifecycle 2>/dev/null || true)
  if [ "$status" -eq 0 ] && [ "$current" != "$expected" ]; then
    status=1
  elif [ "$status" -eq 0 ] && [ -n "$lifecycle" ]; then
    case "$lifecycle" in
      teardown:*) existing_owner=${lifecycle#teardown:} ;;
      *) status=1 ;;
    esac
    existing_token=${existing_owner%%:*}
    if [ "$status" -eq 0 ] && { [ -z "$resume_token" ] || [ "$resume_token" != "$existing_token" ] || fm_meta_teardown_owner_live "$existing_owner"; }; then
      status=1
    fi
  fi
  tmp="$meta.tmp.$$"
  if [ "$status" -eq 0 ]; then
    { grep -v '^lifecycle=' "$meta" || true; printf 'lifecycle=teardown:%s\n' "$owner"; } > "$tmp" || status=$?
  fi
  if [ "$status" -eq 0 ]; then
    mv "$tmp" "$meta" || status=$?
  else
    rm -f "$tmp"
  fi
  [ "$status" -ne 0 ] || claimed=$(fm_meta_identity_unlocked "$meta") || status=$?
  fm_meta_lock_release "$meta"
  [ "$status" -eq 0 ] || return "$status"
  printf '%s' "$claimed"
}

fm_meta_release_teardown() {  # <meta-path> <owner>
  local meta=$1 owner=$2 lifecycle tmp status=0
  fm_meta_lock_acquire "$meta" || return 1
  lifecycle=$(fm_meta_value_unlocked "$meta" lifecycle) || status=$?
  [ "$status" -ne 0 ] || [ "$lifecycle" = "teardown:$owner" ] || status=1
  tmp="$meta.tmp.$$"
  if [ "$status" -eq 0 ]; then
    { grep -v '^lifecycle=' "$meta" || true; } > "$tmp" || status=$?
  fi
  if [ "$status" -eq 0 ]; then
    mv "$tmp" "$meta" || status=$?
  else
    rm -f "$tmp"
  fi
  fm_meta_lock_release "$meta"
  return "$status"
}

fm_meta_identity() {  # <meta-path>
  local meta=$1 identity status=0
  fm_meta_lock_acquire "$meta" || return 1
  identity=$(fm_meta_identity_unlocked "$meta") || status=$?
  fm_meta_lock_release "$meta"
  [ "$status" -eq 0 ] || return "$status"
  printf '%s' "$identity"
}

fm_meta_create_from_file() {  # <meta-path> <source-path>
  local meta=$1 source=$2 status=0
  [ -f "$source" ] || return 1
  fm_meta_lock_acquire "$meta" || return 1
  if [ -e "$meta" ]; then
    status=1
  else
    mv "$source" "$meta" || status=$?
  fi
  fm_meta_lock_release "$meta"
  return "$status"
}

fm_meta_remove_if_identity() {  # <meta-path> <expected-identity> [related-path...]
  local meta=$1 expected=$2 current status=0
  shift 2
  fm_meta_lock_acquire "$meta" || return 1
  current=$(fm_meta_identity_unlocked "$meta") || status=$?
  if [ "$status" -eq 0 ] && [ "$current" != "$expected" ]; then
    status=1
  fi
  if [ "$status" -eq 0 ]; then
    rm -f "$meta" "$@" || status=$?
  fi
  fm_meta_lock_release "$meta"
  return "$status"
}
