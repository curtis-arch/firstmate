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

fm_meta_remove() {  # <meta-path>
  local meta=$1 status=0
  [ -e "$meta" ] || return 0
  fm_meta_lock_acquire "$meta" || return 1
  rm -f "$meta" || status=$?
  fm_meta_lock_release "$meta"
  return "$status"
}
