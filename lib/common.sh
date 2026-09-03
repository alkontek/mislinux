# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Shared helpers for MIS Linux bootstrap.

umask 022

misllog() {
  local level=$1
  shift
  printf '%s [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "$*"
}

info() { misllog INFO "$*"; }
warn() { misllog WARN "$*" >&2; }
die()  { misllog ERROR "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing command: $c"
  done
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "this action requires root"
}

require_lfs_set() {
  [[ -n "${LFS:-}" ]] || die "LFS is not set (edit config/misl.conf or export LFS)"
}

misl_root() {
  # Directory containing the misl entrypoint.
  printf '%s\n' "${MISL_ROOT:?}"
}
