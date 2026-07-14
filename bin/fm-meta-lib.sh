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
  for key in window worktree project backend terminal orca_worktree_id orca_pane_key home; do
    value=$(grep "^$key=" "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    printf '%s=%s\n' "$key" "$value"
  done
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
