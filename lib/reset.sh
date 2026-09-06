# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# misl reset: put an overlay tree back to the base it was before the
# first overlay was applied. See docs/overlays.md.
#
# The first `misl overlay apply` of a non-default overlay on a tree with
# no overlay applied saves a snapshot of every path overlays edit in
# place (MISL_RESET_PATHS) to $LFS/var/lib/misl/reset/. Reset removes
# what the overlays own (owned ledgers, firmware.files), then restores
# those paths exactly from the snapshot. The snapshot is kept.

# Paths (relative to $LFS) that overlay apply can edit outside the
# owned ledgers. cloud edits /etc and /root in place; the overlay and
# firmware ledgers live under var/lib/misl.
MISL_RESET_PATHS="etc root var/lib/cloud var/lib/misl/overlays var/lib/misl/firmware var/lib/misl/cloud.report usr/lib/misl"

misl_reset_dir() {
  require_lfs_set
  printf '%s/var/lib/misl/reset\n' "${LFS%/}"
}

misl_reset_have() { [[ -f $(misl_reset_dir)/manifest && -f $(misl_reset_dir)/pre-overlay.tar.gz ]]; }

# tar flags for owners, perms and (when this tar has them) xattrs/ACLs.
misl_reset_tar_flags() {
  local fl=(--numeric-owner)
  tar --xattrs -cf /dev/null -T /dev/null 2>/dev/null && fl+=(--xattrs --xattrs-include='*')
  tar --acls -cf /dev/null -T /dev/null 2>/dev/null && fl+=(--acls)
  printf '%s\n' "${fl[@]}"
}

# Any overlay stamp on the tree (nested or 0.3 flat)?
misl_reset_any_applied() {
  local st
  st=$(misl_overlay_state_root)
  [[ -d $st ]] && find "$st" -name applied -type f 2>/dev/null | grep . >/dev/null
}

# Called by misl_overlay_apply before anything is written.
misl_reset_snapshot_take() {
  local dir dest p tmp present=() flags=()
  misl_reset_have && return 0
  if misl_reset_any_applied; then
    warn "no reset snapshot: overlays were applied on this tree before misl had reset; ./misl reset cannot restore it (rebuild instead)"
    return 0
  fi
  dir=$(misl_reset_dir)
  dest=${LFS%/}
  # Holds /etc/shadow: owner-only.
  mkdir -p "$dir"
  chmod 0700 "$dir"
  tmp=$dir/manifest.new
  {
    printf 'misl_version=%s\n' "${MISL_VERSION:-unknown}"
    printf 'when=%s\n' "$(date -u +%FT%TZ)"
    printf 'lfs=%s\n' "$LFS"
  } >"$tmp"
  for p in $MISL_RESET_PATHS; do
    if [[ -e $dest/$p || -L $dest/$p ]]; then
      present+=("$p")
      printf 'path=%s\n' "$p" >>"$tmp"
    else
      printf 'absent=%s\n' "$p" >>"$tmp"
    fi
  done
  read -ra flags <<<"$(misl_reset_tar_flags | tr '\n' ' ')"
  if (( ${#present[@]} )); then
    tar "${flags[@]}" -C "$dest" -czpf "$dir/pre-overlay.tar.gz" -- "${present[@]}" \
      || { rm -f "$dir/pre-overlay.tar.gz" "$tmp"; die "reset snapshot: tar failed"; }
  else
    tar -C "$dest" -czf "$dir/pre-overlay.tar.gz" -T /dev/null
  fi
  mv -f "$tmp" "$dir/manifest"
  info "reset snapshot saved: $dir (./misl reset puts the tree back to this point)"
}

_misl_reset_kv() { grep "^$1=" "$(misl_reset_dir)/manifest" | sed "s|^$1=||"; }

misl_reset_info() {
  require_lfs_set
  local dir q any=0
  dir=$(misl_reset_dir)
  printf 'LFS=%s\n' "$LFS"
  if ! misl_reset_have; then
    printf 'reset snapshot: none (taken on the first overlay apply on a base tree)\n'
    return 0
  fi
  printf 'reset snapshot: %s\n' "$dir"
  printf '  taken:   %s (misl %s)\n' "$(_misl_reset_kv when)" "$(_misl_reset_kv misl_version)"
  printf '  size:    %s\n' "$(du -sh "$dir/pre-overlay.tar.gz" | cut -f1)"
  printf '  restores exactly (files added since are deleted):\n'
  _misl_reset_kv path | sed 's|^|    /|'
  if _misl_reset_kv absent | grep . >/dev/null; then
    printf '  removes (did not exist then):\n'
    _misl_reset_kv absent | sed 's|^|    /|'
  fi
  printf '  removes the files and firmware owned by:\n'
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    misl_overlay_applied "$q" || continue
    any=1
    printf '    %s\n' "$q"
  done <<<"$(misl_overlay_all)"
  (( any )) || printf '    (no overlay applied)\n'
}

misl_reset_explain() {
  cat <<EOF
misl reset puts $LFS back to the base tree as it was before the first
overlay was applied ($(_misl_reset_kv when)). It will:
  - remove every file, link and firmware file an overlay installed
  - restore these paths exactly from the snapshot, deleting anything
    added under them since: $(_misl_reset_kv path | sed 's|^|/|' | tr '\n' ' ')
  - clear the overlay stamps; os-release MISL_OVERLAYS goes back to the base
  - keep the snapshot, so reset can be run again
It does not rebuild or remove packages (package-group builds, cloud-init
from cloud install stay), and does not change the compiled kernel
(kernel.list extras stay until MISL_FORCE=1 ./misl build 10-boot/linux).
Changes made under those paths after the snapshot by other commands
(for example ./misl config apply) are lost too.
EOF
}

misl_reset_confirm() {
  [[ ${MISL_FORCE:-0} == 1 ]] && return 0
  if [[ -t 0 ]]; then
    local ans=""
    printf 'type yes to reset %s: ' "$LFS" >&2
    read -r ans || true
    [[ $ans == yes ]] && return 0
    die "reset cancelled"
  fi
  die "reset needs confirmation: run it in a terminal and type yes, or set MISL_FORCE=1"
}

misl_reset_run() {
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
  if [[ ${LFS:-} == / ]]; then
    die "reset runs on the host against \$LFS (overlays are applied there); it does not reset a running system"
  fi
  misl_reset_have || die "no reset snapshot in $(misl_reset_dir): this tree has no record of its pre-overlay state. rebuild it to get a clean base"
  local dest dir q qs p flags=()
  dest=${LFS%/}
  dir=$(misl_reset_dir)
  misl_reset_explain
  misl_reset_confirm
  # Owned files and firmware, children first (reverse qname order).
  qs=$(misl_overlay_all | LC_ALL=C sort -r)
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    misl_overlay_migrate "$q"
    misl_overlay_applied "$q" || continue
    info "reset: removing files owned by $q"
    misl_overlay_undo_owned "$q"
    if declare -F misl_fw_undo >/dev/null; then misl_fw_undo "$q"; fi
  done <<<"$qs"
  for p in $(_misl_reset_kv path) $(_misl_reset_kv absent); do
    [[ -n $p && $p != /* && $p != *..* ]] || die "reset manifest: bad path $p"
    rm -rf "${dest:?}/$p"
  done
  read -ra flags <<<"$(misl_reset_tar_flags | tr '\n' ' ')"
  tar "${flags[@]}" -C "$dest" -xzpf "$dir/pre-overlay.tar.gz" || die "reset: restore from $dir failed"
  misl_overlay_write_os_release
  info "reset done: $LFS is back to the pre-overlay base (snapshot kept in $dir)"
}

misl_reset() {
  case ${1:-} in
    "") misl_reset_run ;;
    --all|all) shift; misl_reset_all "$@" ;;
    --info|info|status) misl_reset_info ;;
    -h|--help|help)
      printf '%s\n' "usage: misl reset [--info|status] | misl reset --all [--dry-run] [--lfs-home]" \
        "  put \$LFS back to the base tree saved before the first overlay apply" \
        "  (needs: type yes, or MISL_FORCE=1). --info: what reset would restore" \
        "  --all: wipe \$LFS and build state; keep downloads and built images"
      ;;
    *) die "usage: misl reset [--info|status] | misl reset --all [--dry-run] [--lfs-home]" ;;
  esac
}

# ---------------------------------------------------------------------
# misl reset --all: wipe $LFS and every build intermediate so a clean
# build can run again. Keeps downloads ($MISL_SNAPSHOT: sources,
# patches, docs, incoming/), the repo, config/misl.conf, the lfs user,
# the $LFS and boot-partition mounts, the partition table, and every
# built image (*.img, *.img.gz, *.iso) anywhere.

# Mount points from /proc/self/mountinfo (octal escapes decoded).
# MISL_MOUNTINFO overrides the file (fixtures).
_misl_reset_all_mounts() {
  local f=${MISL_MOUNTINFO:-/proc/self/mountinfo}
  [[ -r $f ]] || return 0
  awk '{print $5}' "$f" | while IFS= read -r m; do printf '%b\n' "$m"; done
}

# Mounts at or under $1.
_misl_reset_all_mounts_under() {
  local root=${1%/} m
  while IFS= read -r m; do
    [[ -n $m ]] || continue
    [[ $m == "$root" || $m == "$root"/* ]] && printf '%s\n' "$m"
  done <<<"$(_misl_reset_all_mounts)"
  return 0
}

# Kept mounts under $LFS: $LFS itself and the boot partition.
_misl_reset_all_kept() {
  local d=$1 m=$2
  [[ $m == "$d" || $m == "$d/boot" || $m == "$d/boot/efi" ]]
}

# Mounts misl makes: unmounted (deepest first) before the wipe.
_misl_reset_all_ours() {
  local d=$1
  printf '%s\n' "$d/etc/resolv.conf" "$d/usr/src/misl/mislinux" \
    "$d/dev/shm" "$d/dev/pts" "$d/dev" "$d/proc" "$d/sys" "$d/run"
}

_misl_reset_all_is_ours() {
  local d=$1 m=$2 o
  while IFS= read -r o; do [[ $m == "$o" ]] && return 0; done <<<"$(_misl_reset_all_ours "$d")"
  return 1
}

_misl_reset_all_is_image() {
  case ${1##*/} in *.img|*.img.gz|*.iso) return 0 ;; esac
  return 1
}

_misl_reset_all_real() { readlink -f -- "$1" 2>/dev/null || printf '%s\n' "$1"; }

_misl_reset_all_under() {
  # true when $2 is $1 or below it
  [[ $2 == "$1" || $2 == "$1"/* ]]
}

misl_reset_all_guard() {
  local d snap root
  [[ -n ${LFS:-} ]] || die "reset --all: LFS is empty"
  [[ ${LFS} != / ]] || die "reset --all runs on the host against \$LFS; it never wipes a running system (LFS=/)"
  [[ -d $LFS ]] || die "reset --all: LFS=$LFS is not a directory"
  d=$(_misl_reset_all_real "$LFS")
  [[ $d != / && -n $d ]] || die "reset --all: LFS=$LFS resolves to /"
  root=$(_misl_reset_all_real "$MISL_ROOT")
  if [[ -n ${MISL_SNAPSHOT:-} ]]; then
    snap=$(_misl_reset_all_real "$MISL_SNAPSHOT")
    _misl_reset_all_under "$d" "$snap" && die "reset --all: MISL_SNAPSHOT=$MISL_SNAPSHOT is inside \$LFS (downloads must stay)"
    _misl_reset_all_under "$snap" "$d" && die "reset --all: LFS=$LFS is inside MISL_SNAPSHOT"
  fi
  _misl_reset_all_under "$root" "$d" && die "reset --all: LFS=$LFS is inside the repo"
  _misl_reset_all_under "$d" "$root" && die "reset --all: the repo $MISL_ROOT is inside \$LFS"
  printf '%s\n' "$d"
}

# Children of $1 to delete, skipping kept mount points (and lost+found
# at a filesystem top). Descends into dirs that hold a kept mount.
_misl_reset_all_targets() {
  local dir=$1 lfs=$2 c m hold
  local -a kept=()
  while IFS= read -r m; do
    [[ -n $m ]] && _misl_reset_all_kept "$lfs" "$m" && kept+=("$m")
  done <<<"$(_misl_reset_all_mounts_under "$lfs")"
  for c in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -e $c || -L $c ]] || continue
    if [[ ${c##*/} == lost+found ]]; then
      [[ $dir == "$lfs" ]] && continue
      for m in "${kept[@]}"; do [[ $dir == "$m" ]] && continue 2; done
    fi
    hold=0
    for m in "${kept[@]}"; do
      [[ $c == "$m" ]] && { hold=2; break; }
      [[ $m == "$c"/* ]] && hold=1
    done
    # hold: c is the boot mount (clear its contents) or holds it.
    if (( hold )); then _misl_reset_all_targets "$c" "$lfs"; else printf '%s\n' "$c"; fi
  done
}

misl_reset_all_tmpdir() { printf '%s\n' "${MISL_RESET_TMPDIR:-/var/tmp}"; }

# Non-image files and empty dirs under $tmpdir/misl-* (skips anything
# with a mount inside).
_misl_reset_all_tmp_targets() {
  local t p
  for t in "$(misl_reset_all_tmpdir)"/misl-*; do
    [[ -e $t || -L $t ]] || continue
    [[ -n $(_misl_reset_all_mounts_under "$(_misl_reset_all_real "$t")") ]] && continue
    if [[ -d $t && ! -L $t ]]; then
      while IFS= read -r -d '' p; do
        _misl_reset_all_is_image "$p" || printf '%s\n' "$p"
      done < <(find "$t" -xdev ! -type d -print0)
    else
      _misl_reset_all_is_image "$t" || printf '%s\n' "$t"
    fi
  done
}

_misl_reset_all_home_targets() {
  local home
  home=$(getent passwd lfs | awk -F: '{print $6}')
  [[ -n $home && -d $home ]] || return 0
  if [[ -d $home/mislinux && ! -L $home/mislinux ]] && \
     [[ $(_misl_reset_all_real "$home/mislinux") != "$(_misl_reset_all_real "$MISL_ROOT")" ]] && \
     [[ -z $(_misl_reset_all_mounts_under "$home/mislinux") ]]; then
    printf '%s\n' "$home/mislinux"
  fi
  [[ -L $home/misl-1.0-systemd ]] && printf '%s\n' "$home/misl-1.0-systemd"
  return 0
}

# Built images inside $LFS: refuse rather than delete them.
_misl_reset_all_images_in() {
  find "$1" -xdev \( -name 'misl-*.img' -o -name 'misl-*.img.gz' -o -name 'misl-*.iso' \) ! -type d -print 2>/dev/null
  local m
  while IFS= read -r m; do
    [[ -n $m && $m != "$1" ]] && _misl_reset_all_kept "$1" "$m" && \
      find "$m" -xdev \( -name 'misl-*.img' -o -name 'misl-*.img.gz' -o -name 'misl-*.iso' \) ! -type d -print 2>/dev/null
  done <<<"$(_misl_reset_all_mounts_under "$1")"
  return 0
}

misl_reset_all() {
  local dry=0 home=0 a d m t imgs
  local -a bad=() ours=() targets=() tmps=() homes=()
  for a in "$@"; do
    case $a in
      --dry-run|-n) dry=1 ;;
      --lfs-home) home=1 ;;
      *) die "usage: misl reset --all [--dry-run] [--lfs-home]" ;;
    esac
  done
  d=$(misl_reset_all_guard) || exit 1
  while IFS= read -r m; do
    [[ -n $m ]] || continue
    _misl_reset_all_kept "$d" "$m" && continue
    if _misl_reset_all_is_ours "$d" "$m"; then ours+=("$m"); else bad+=("$m"); fi
  done <<<"$(_misl_reset_all_mounts_under "$d")"
  (( ${#bad[@]} == 0 )) || die "reset --all: unexpected mounts under \$LFS (unmount them first): ${bad[*]}"
  # Unmount children before parents (dev/pts and dev/shm before dev).
  (( ${#ours[@]} )) && mapfile -t ours < <(printf '%s\n' "${ours[@]}" | LC_ALL=C sort -r)
  imgs=$(_misl_reset_all_images_in "$d")
  [[ -z $imgs ]] || die "reset --all: built images inside \$LFS (move them out first; images are never deleted): $(tr '\n' ' ' <<<"$imgs")"

  mapfile -t targets < <(_misl_reset_all_targets "$d" "$d")
  mapfile -t tmps < <(_misl_reset_all_tmp_targets)
  (( home )) && mapfile -t homes < <(_misl_reset_all_home_targets)

  printf 'misl reset --all on LFS=%s\n' "$d"
  printf 'keeps: MISL_SNAPSHOT=%s (downloads, incoming/), the repo, config/misl.conf,\n' "${MISL_SNAPSHOT:-unset}"
  printf '%s\n' "       the lfs user, the \$LFS and boot mounts, partitions, and all built images"
  if (( ${#ours[@]} )); then
    printf 'unmounts:\n'; printf '  %s\n' "${ours[@]}"
  fi
  printf 'deletes:\n'
  for t in "${targets[@]}" "${tmps[@]}" "${homes[@]}"; do
    [[ -n $t ]] || continue
    printf '  %-8s %s\n' "$(du -sh --one-file-system -- "$t" 2>/dev/null | cut -f1)" "$t"
  done
  (( ${#targets[@]} + ${#tmps[@]} + ${#homes[@]} )) || printf '  (nothing)\n'
  if (( dry )); then
    info "reset --all: dry run, nothing deleted"
    return 0
  fi
  misl_reset_confirm
  if (( ${#ours[@]} )); then
    require_root
    for m in "${ours[@]}"; do
      mountpoint -q "$m" 2>/dev/null || continue
      umount "$m" || die "reset --all: cannot umount $m (a process may still use it; check: fuser -vm $m)"
    done
    while IFS= read -r m; do
      [[ -n $m ]] || continue
      _misl_reset_all_kept "$d" "$m" || die "reset --all: $m is still mounted"
    done <<<"$(_misl_reset_all_mounts_under "$d")"
  fi
  for t in "${targets[@]}" "${homes[@]}"; do
    [[ -n $t ]] || continue
    rm -rf --one-file-system -- "$t" || die "reset --all: cannot remove $t"
  done
  for t in "${tmps[@]}"; do
    [[ -n $t ]] && rm -f -- "$t"
  done
  for t in "$(misl_reset_all_tmpdir)"/misl-*; do
    [[ -d $t && ! -L $t ]] && find "$t" -xdev -depth -type d -empty -delete 2>/dev/null
  done
  info "reset --all done: $d is empty; downloads and images kept. next: ./misl prep, ./misl sources stage, build"
}
