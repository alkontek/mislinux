# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Named overlays on top of the base tree. See docs/overlays.md.

misl_overlay_home() { printf '%s/overlays\n' "${MISL_ROOT:?}"; }

misl_overlay_state_root() {
  require_lfs_set
  if [[ ${LFS:-} == / ]]; then
    printf '/var/lib/misl/overlays\n'
  else
    printf '%s/var/lib/misl/overlays\n' "${LFS%/}"
  fi
}

misl_overlay_dest() {
  require_lfs_set
  if [[ ${LFS:-} == / ]]; then
    printf '\n'
  else
    printf '%s\n' "${LFS%/}"
  fi
}

misl_overlay_canon() {
  local n=$1
  if [[ $n == */* ]]; then
    n=${n##*/}
  fi
  printf '%s\n' "$n"
}

misl_overlay_qname() {
  local n=$1
  misl_overlay_load "$n"
  if [[ -n ${OVERLAY_PARENT:-} ]]; then
    printf '%s/%s\n' "$OVERLAY_PARENT" "$OVERLAY_NAME"
  else
    printf '%s\n' "$OVERLAY_NAME"
  fi
}

misl_overlay_exists() {
  local n
  n=$(misl_overlay_canon "$1")
  [[ -f $(misl_overlay_home)/$n/overlay.conf ]]
}

misl_overlay_load() {
  local n f
  n=$(misl_overlay_canon "$1")
  f=$(misl_overlay_home)/$n/overlay.conf
  [[ -f $f ]] || die "no overlay $n"
  OVERLAY_NAME=$n
  OVERLAY_TITLE=$n
  OVERLAY_CLASS=
  OVERLAY_REQUIRES=
  OVERLAY_STATUS=stub
  OVERLAY_KERNEL=0
  OVERLAY_PARENT=
  OVERLAY_PRIORITY=100
  OVERLAY_DEFAULT=0
  local key val line
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    key=${line%%=*}
    val=${line#*=}
    val=${val#\"}
    val=${val%\"}
    val=${val#\'}
    val=${val%\'}
    case $key in
      name) OVERLAY_NAME=$val ;;
      title) OVERLAY_TITLE=$val ;;
      class) OVERLAY_CLASS=$val ;;
      requires) OVERLAY_REQUIRES=$val ;;
      status) OVERLAY_STATUS=$val ;;
      kernel) OVERLAY_KERNEL=$val ;;
      parent) OVERLAY_PARENT=$val ;;
      priority) OVERLAY_PRIORITY=$val ;;
      default) OVERLAY_DEFAULT=$val ;;
    esac
  done <"$f"
}

misl_overlay_applied() {
  local n=$1
  [[ -f $(misl_overlay_state_root)/$n/applied ]]
}

misl_overlay_stamp() {
  local n=$1 dir
  dir=$(misl_overlay_state_root)/$n
  mkdir -p "$dir"
  {
    printf 'name=%s\n' "$n"
    printf 'when=%s\n' "$(date -u +%FT%TZ)"
  } >"$dir/applied"
  misl_overlay_write_os_release
}

misl_overlay_unstamp() {
  local n=$1 dir
  dir=$(misl_overlay_state_root)/$n
  rm -f "$dir/applied" "$dir/owned"
  rmdir "$dir" 2>/dev/null || true
  misl_overlay_write_os_release
}

# Record a dest-absolute path as owned by the overlay currently applying.
misl_overlay_own() {
  local path=$1 n dir rel dest
  n=${MISL_OVERLAY_APPLYING:-}
  [[ -n $n ]] || return 0
  dest=$(misl_overlay_dest)
  dir=$(misl_overlay_state_root)/$n
  mkdir -p "$dir"
  rel=$path
  if [[ -n $dest && $path == "$dest"/* ]]; then
    rel=${path#"$dest"}
  fi
  [[ $rel == /* ]] || rel=/$rel
  if [[ -f $dir/owned ]] && grep -qxF "$rel" "$dir/owned"; then
    return 0
  fi
  printf '%s\n' "$rel" >>"$dir/owned"
}

# Delete only paths listed in overlays/<name>/owned (files and symlinks).
misl_overlay_undo_owned() {
  local n=$1 dest f path
  dest=$(misl_overlay_dest)
  f=$(misl_overlay_state_root)/$n/owned
  [[ -f $f ]] || return 0
  while IFS= read -r path || [[ -n $path ]]; do
    [[ -n $path ]] || continue
    if [[ -n $dest ]]; then
      path=${dest}${path}
    fi
    if [[ -L $path || -f $path ]]; then
      rm -f "$path"
      info "removed $path"
    fi
  done <"$f"
}

misl_overlay_active_qnames() {
  local f n
  for f in "$(misl_overlay_home)"/*/overlay.conf; do
    [[ -f $f ]] || continue
    n=$(basename "$(dirname "$f")")
    misl_overlay_load "$n"
    if [[ -n ${LFS:-} ]] && misl_overlay_applied "$n" 2>/dev/null; then
      misl_overlay_qname "$n"
    elif [[ ${OVERLAY_DEFAULT:-0} == 1 || ${OVERLAY_DEFAULT:-} == yes ]]; then
      misl_overlay_qname "$n"
    fi
  done
}

misl_overlay_write_os_release() {
  local dest root rel line names
  dest=$(misl_overlay_dest)
  root=${dest:-}
  rel=${root}/usr/lib/os-release
  [[ -f $rel ]] || rel=${root}/etc/os-release
  [[ -f $rel ]] || return 0
  names=$(misl_overlay_active_qnames | tr '\n' ' ')
  names=${names%% }
  line="MISL_OVERLAYS=\"${names}\""
  if grep -q '^MISL_OVERLAYS=' "$rel"; then
    sed -i "s|^MISL_OVERLAYS=.*|$line|" "$rel"
  else
    printf '%s\n' "$line" >>"$rel"
  fi
  if [[ -f ${root}/etc/os-release && ! -L ${root}/etc/os-release ]]; then
    if grep -q '^MISL_OVERLAYS=' "${root}/etc/os-release"; then
      sed -i "s|^MISL_OVERLAYS=.*|$line|" "${root}/etc/os-release"
    else
      printf '%s\n' "$line" >>"${root}/etc/os-release"
    fi
  fi
}

# Dependents that are currently applied (overlays that require $1).
misl_overlay_dependents_applied() {
  local target=$1 d req
  for d in "$(misl_overlay_home)"/*/overlay.conf; do
    [[ -f $d ]] || continue
    local n
    n=$(basename "$(dirname "$d")")
    misl_overlay_load "$n"
    for req in $OVERLAY_REQUIRES; do
      if [[ $req == "$target" ]] && misl_overlay_applied "$n"; then
        printf '%s\n' "$n"
      fi
    done
  done
}

misl_overlay_applyable() {
  case ${1:-} in
    alpha|beta|rc|stable) return 0 ;;
    *) return 1 ;;
  esac
}

# Expand names + requires. Die on stub/missing.
misl_overlay_resolve() {
  local n req out=() seen=" "
  _ov_add() {
    local x=$1 r
    x=$(misl_overlay_canon "$x")
    [[ $seen == *" $x "* ]] && return 0
    misl_overlay_exists "$x" || die "no overlay $x"
    misl_overlay_load "$x"
    if ! misl_overlay_applyable "$OVERLAY_STATUS"; then
      die "overlay $x is $OVERLAY_STATUS (apply: alpha|beta|rc|stable)"
    fi
    for r in $OVERLAY_REQUIRES; do
      _ov_add "$r"
    done
    seen+=" $x "
    out+=("$x")
  }
  for n in "$@"; do
    _ov_add "$n"
  done
  printf '%s\n' "${out[@]}"
}

misl_overlay_list() {
  local header=1 f n mark q pri
  case ${1:-} in
    --header|-H) header=1 ;;
    --no-header) header=0 ;;
  esac
  {
    [[ $header == 1 ]] && printf '%s\t%s\t%s\t%s\t%s\n' NAME STATUS ON CLASS TITLE
    for f in "$(misl_overlay_home)"/*/overlay.conf; do
      [[ -f $f ]] || continue
      n=$(basename "$(dirname "$f")")
      misl_overlay_load "$n"
      pri=${OVERLAY_PRIORITY:-100}
      q=$(misl_overlay_qname "$n")
      mark=off
      if [[ -n ${LFS:-} ]] && misl_overlay_applied "$n" 2>/dev/null; then
        mark=on
      elif [[ ${OVERLAY_DEFAULT:-0} == 1 || ${OVERLAY_DEFAULT:-} == yes ]]; then
        mark=default
      fi
      printf '%04d\t%s\t%s\t%s\t%s\t%s\n' "$pri" "$q" "$OVERLAY_STATUS" "$mark" "$OVERLAY_CLASS" "$OVERLAY_TITLE"
    done | sort -n -k1,1 -k2,2 | cut -f2-
  } | misl_table
}

misl_overlay_status() {
  require_lfs_set
  local f n
  printf 'LFS=%s\n' "$LFS"
  printf 'applied:\n'
  local any=0
  for f in "$(misl_overlay_state_root)"/*/applied; do
    [[ -f $f ]] || continue
    any=1
    n=$(basename "$(dirname "$f")")
    printf '  %s  (%s)\n' "$n" "$(tr '\n' ' ' <"$f")"
  done
  if [[ $any -eq 0 ]]; then
    printf '  (none)\n'
  fi
}

misl_overlay_run_hook() {
  local n=$1 hook=$2
  local f
  f=$(misl_overlay_home)/$n/$hook
  [[ -f $f ]] || return 0
  # shellcheck disable=SC1090
  . "$f"
}

misl_overlay_apply_one() {
  local n=$1
  misl_overlay_load "$n"
  info "overlay apply $n ($OVERLAY_TITLE)"
  MISL_OVERLAY_APPLYING=$n
  export MISL_OVERLAY_APPLYING
  misl_overlay_run_hook "$n" apply.sh
  unset MISL_OVERLAY_APPLYING
  misl_overlay_stamp "$n"
}

misl_overlay_apply() {
  local n
  [[ $# -gt 0 ]] || die "usage: misl overlay apply <name>..."
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
  if [[ ${LFS:-} == / ]]; then
    die "overlay apply runs on the Fedora host. exit the chroot first"
  fi
  local names
  names=$(misl_overlay_resolve "$@")
  while IFS= read -r n; do
    [[ -n $n ]] || continue
    misl_overlay_apply_one "$n"
  done <<<"$names"
  info "overlays applied: $(printf '%s' "$names" | tr '\n' ' ')"
  info "next: ./misl enter"
  if misl_overlay_applied cloud; then
    info "next: MISL_FORCE=1 ./misl build 10-boot/linux"
    info "next: ./misl overlay install cloud   (or: ./misl cloud install)"
  fi
}

misl_overlay_undo_one() {
  local n=$1 dep
  n=$(misl_overlay_canon "$n")
  misl_overlay_exists "$n" || die "no overlay $n"
  misl_overlay_load "$n"
  if [[ ${OVERLAY_DEFAULT:-0} == 1 || ${OVERLAY_DEFAULT:-} == yes ]]; then
    die "overlay $n is the default (the base tree). not undone"
  fi
  dep=$(misl_overlay_dependents_applied "$n" | tr '\n' ' ')
  if [[ -n ${dep// /} ]]; then
    die "undo $n blocked: still applied: $dep"
  fi
  info "overlay undo $n"
  misl_overlay_undo_owned "$n"
  misl_overlay_run_hook "$n" undo.sh || true
  misl_overlay_unstamp "$n"
}

misl_overlay_undo() {
  local n
  [[ $# -gt 0 ]] || die "usage: misl overlay undo <name>..."
  require_lfs_set
  # undo the names as given (children before parents)
  for n in "$@"; do
    misl_overlay_undo_one "$n"
  done
}

# Kernel extras: any applied overlay with kernel=1, or MISL_CLOUD=1.
misl_overlay_kernel_wanted() {
  [[ ${MISL_CLOUD:-0} == 1 ]] && return 0
  local root f n
  if [[ ${LFS:-} == / || -z ${LFS:-} ]]; then
    root=/var/lib/misl
  else
    root=${LFS%/}/var/lib/misl
  fi
  [[ -f $root/overlays/cloud/applied ]] && return 0
  for f in "$root"/overlays/*/applied; do
    [[ -f $f ]] || continue
    n=$(basename "$(dirname "$f")")
    misl_overlay_exists "$n" || continue
    misl_overlay_load "$n"
    [[ ${OVERLAY_KERNEL:-0} == 1 ]] && return 0
  done
  return 1
}

misl_overlay_kernel_configs() {
  local n f line root
  if [[ ${LFS:-} == / || -z ${LFS:-} ]]; then
    root=/var/lib/misl
  else
    root=${LFS%/}/var/lib/misl
  fi
  for f in "$(misl_overlay_home)"/*/kernel.list; do
    [[ -f $f ]] || continue
    n=$(basename "$(dirname "$f")")
    if [[ -f $root/overlays/$n/applied ]]; then
      while IFS= read -r line; do
        [[ $line =~ ^CONFIG_ ]] && printf '%s\n' "$line"
      done <"$f"
    fi
  done
}

misl_overlay_install() {
  local n=${1:-cloud}
  case $n in
    cloud) misl_cloud_install ;;
    *) die "overlay install: only cloud has an install hook (cloud-init)" ;;
  esac
}

misl_overlay() {
  local sub=${1:-list}
  shift || true
  case $sub in
    list) misl_overlay_list "$@" ;;
    status|show) misl_overlay_status ;;
    apply) misl_overlay_apply "$@" ;;
    undo|revert) misl_overlay_undo "$@" ;;
    install) misl_overlay_install "$@" ;;
    -h|--help|help)
      printf '%s\n' "usage: misl overlay list [--header|--no-header]|status|apply <name...>|undo <name>|install cloud"
      ;;
    *) die "usage: misl overlay list|status|apply|undo|install" ;;
  esac
}
