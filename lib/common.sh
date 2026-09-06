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

# Column reports (cloud.report, 09-config.report, …).
# Keys in a 14-char field; list items two-space indented. No mkdir noise.
misl_report_begin() {
  local file=$1 title=$2
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$title" >"$file"
}

misl_report_kv() {
  local file=$1 key=$2
  shift 2
  printf '  %-14s %s\n' "$key" "$*" >>"$file"
}

misl_report_section() {
  local file=$1 name=$2
  printf '\n%s\n' "$name" >>"$file"
}

misl_report_item() {
  local file=$1
  shift
  printf '  %s\n' "$*" >>"$file"
}

# Tab-separated rows on stdin. Pads columns to the widest cell.
misl_table() {
  local -a rows=()
  local line i maxc=0
  while IFS= read -r line || [[ -n $line ]]; do
    rows+=("$line")
  done
  ((${#rows[@]})) || return 0
  local -a widths=()
  for line in "${rows[@]}"; do
    IFS=$'\t' read -r -a cols <<<"$line"
    (( ${#cols[@]} > maxc )) && maxc=${#cols[@]}
    i=0
    while (( i < ${#cols[@]} )); do
      local w=${#cols[i]}
      if (( w > ${widths[i]:-0} )); then
        widths[i]=$w
      fi
      i=$((i + 1))
    done
  done
  for line in "${rows[@]}"; do
    IFS=$'\t' read -r -a cols <<<"$line"
    i=0
    while (( i < maxc )); do
      (( i > 0 )) && printf '  '
      printf '%-*s' "${widths[i]:-0}" "${cols[i]:-}"
      i=$((i + 1))
    done
    printf '\n'
  done
}

# dest-relative path for report lists (/etc/… not /mnt/misl/etc/…).
misl_report_relpath() {
  local dest=$1 path=$2 rel
  dest=${dest%/}
  if [[ -n $dest && $path == "$dest"/* ]]; then
    printf '%s\n' "${path#"$dest"}"
  elif [[ -z $dest ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$path"
  fi
}

# chown -R that never crosses a mount: binds under the dirs (the repo at
# $LFS/usr/src/misl/mislinux, kernfs) keep their owner.
# usage: misl_chown_tree OWNER [--from USER] DIR...
misl_chown_tree() {
  local own=$1 from= m d f=${MISL_MOUNTINFO:-/proc/self/mountinfo}
  local -a dirs=() prune=()
  shift
  if [[ ${1:-} == --from ]]; then from=$2; shift 2; fi
  for d in "$@"; do [[ -e $d ]] && dirs+=("${d%/}"); done
  (( ${#dirs[@]} )) || return 0
  if [[ -r $f ]]; then
    while IFS= read -r m; do
      m=$(printf '%b' "$m")
      for d in "${dirs[@]}"; do
        if [[ $m == "$d"/* ]]; then
          prune+=(${prune[@]:+-o} -path "$m")
          info "chown: skipping mount $m"
        fi
      done
    done < <(awk '{print $5}' "$f")
  fi
  if (( ${#prune[@]} )); then
    find "${dirs[@]}" -xdev \( "${prune[@]}" \) -prune -o ${from:+-user "$from"} -exec chown -h "$own" {} +
  else
    find "${dirs[@]}" -xdev ${from:+-user "$from"} -exec chown -h "$own" {} +
  fi
}
