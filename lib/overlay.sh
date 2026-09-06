# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Named overlays on top of the base tree. See docs/overlays.md.
#
# Nested model: every dir under overlays/ holding overlay.conf is an
# overlay; its qualified name (qname) is the path relative to overlays/
# (cloud/do, desktop/asus/rog-strix-x570). A dir without overlay.conf is
# a grouping dir (desktop/asus); the parent is the nearest ancestor that
# is an overlay. Stamps: <state>/<qname>/applied. 0.3 flat stamps
# (<state>/do/applied) are read as cloud/do and moved on the next write.

misl_overlay_home() { printf '%s/overlays\n' "${MISL_ROOT:-.}"; }

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

# Every qname, sorted. No process substitution (no /dev/fd in chroot).
misl_overlay_all() {
  local home
  home=$(misl_overlay_home)
  [[ -d $home ]] || return 0
  find "$home" -mindepth 2 -name overlay.conf -type f -printf '%P\n' | \
    sed 's|/overlay\.conf$||' | LC_ALL=C sort
}

misl_overlay_is_q() { [[ -n ${1:-} && -f $(misl_overlay_home)/$1/overlay.conf ]]; }

# Folder-implied parent: nearest ancestor dir that is an overlay.
misl_overlay_parent_of() {
  local q=$1
  while [[ $q == */* ]]; do
    q=${q%/*}
    misl_overlay_is_q "$q" && { printf '%s\n' "$q"; return 0; }
  done
  printf '\n'
}

# Ancestors, root first.
misl_overlay_ancestors() {
  local q=$1 p out=()
  p=$(misl_overlay_parent_of "$q")
  while [[ -n $p ]]; do
    out=("$p" "${out[@]}")
    p=$(misl_overlay_parent_of "$p")
  done
  (( ${#out[@]} )) && printf '%s\n' "${out[@]}"
  return 0
}

# Name on the CLI / in requires= -> qname. Exact qname first, then a
# unique leaf (do -> cloud/do). Ambiguous leaf dies.
misl_overlay_canon() {
  local n=${1%/} q hits=()
  [[ -n $n ]] || die "empty overlay name"
  if misl_overlay_is_q "$n"; then
    printf '%s\n' "$n"
    return 0
  fi
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    [[ ${q##*/} == "${n##*/}" ]] && hits+=("$q")
  done <<<"$(misl_overlay_all)"
  case ${#hits[@]} in
    0) die "no overlay $n" ;;
    1) printf '%s\n' "${hits[0]}" ;;
    *) die "overlay name $n is ambiguous: ${hits[*]} (use the qualified name)" ;;
  esac
}

misl_overlay_exists() {
  ( misl_overlay_canon "$1" ) >/dev/null 2>&1
}

misl_overlay_qname() { misl_overlay_canon "$1"; }

misl_overlay_load() {
  local q f implied
  q=$(misl_overlay_canon "$1") || exit 1
  f=$(misl_overlay_home)/$q/overlay.conf
  OVERLAY_NAME=${q##*/}
  OVERLAY_TITLE=$OVERLAY_NAME
  OVERLAY_CLASS=
  OVERLAY_REQUIRES=
  OVERLAY_STATUS=stub
  OVERLAY_KERNEL=0
  OVERLAY_PARENT=
  OVERLAY_PRIORITY=100
  OVERLAY_DEFAULT=0
  OVERLAY_PACKAGES=
  OVERLAY_ONEWAY=0
  local key val line cname="" cparent=""
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
      name) cname=$val ;;
      title) OVERLAY_TITLE=$val ;;
      class) OVERLAY_CLASS=$val ;;
      requires) OVERLAY_REQUIRES=$val ;;
      status) OVERLAY_STATUS=$val ;;
      kernel) OVERLAY_KERNEL=$val ;;
      parent) cparent=$val ;;
      priority) OVERLAY_PRIORITY=$val ;;
      default) OVERLAY_DEFAULT=$val ;;
      packages) OVERLAY_PACKAGES=$val ;;
      oneway) OVERLAY_ONEWAY=$val ;;
    esac
  done <"$f"
  [[ -z $cname || $cname == "$OVERLAY_NAME" ]] || \
    die "overlays/$q/overlay.conf: name=$cname but the folder is $OVERLAY_NAME"
  implied=$(misl_overlay_parent_of "$q")
  # parent= may be the qname or the leaf of the folder-implied parent.
  if [[ -n $cparent && $cparent != "$implied" && $cparent != "${implied##*/}" ]]; then
    die "overlays/$q/overlay.conf: parent=$cparent but the folder implies ${implied:-(none)}"
  fi
  # shellcheck disable=SC2034 # read by callers
  OVERLAY_PARENT=$implied
}

# oneway=1 on the overlay or any ancestor: undo refuses (misl reset).
misl_overlay_is_oneway() {
  local q a
  q=$(misl_overlay_canon "$1") || exit 1
  for a in $(misl_overlay_ancestors "$q") "$q"; do
    misl_overlay_load "$a"
    [[ ${OVERLAY_ONEWAY:-0} == 1 || ${OVERLAY_ONEWAY:-} == yes ]] && return 0
  done
  return 1
}

# Printed before a one-way overlay is applied.
misl_overlay_oneway_notice() {
  local q=$1
  if declare -F "misl_${q%%/*}_notice" >/dev/null; then
    "misl_${q%%/*}_notice"
  else
    printf '%s\n' "==> overlay $q is one-way: its edits cannot be undone." \
      "    The way back is ./misl reset or a rebuild." >&2
  fi
  if declare -F misl_reset_have >/dev/null && ! misl_reset_have; then
    printf '%s\n' "    WARNING: this tree has no reset snapshot, so only a rebuild takes it back." >&2
  fi
}

misl_overlay_is_default() {
  [[ ${OVERLAY_DEFAULT:-0} == 1 || ${OVERLAY_DEFAULT:-} == yes ]]
}

# 0.3 flat stamp dir for a nested qname (do -> <state>/do), or empty.
misl_overlay_legacy_dir() {
  local q=$1 leaf
  [[ $q == */* ]] || return 1
  leaf=${q##*/}
  misl_overlay_is_q "$leaf" && return 1
  printf '%s/%s\n' "$(misl_overlay_state_root)" "$leaf"
}

misl_overlay_applied() {
  local q l
  q=$(misl_overlay_canon "$1" 2>/dev/null) || return 1
  [[ -f $(misl_overlay_state_root)/$q/applied ]] && return 0
  l=$(misl_overlay_legacy_dir "$q") || return 1
  [[ -f $l/applied ]]
}

# Move a 0.3 flat stamp dir to its qname (write paths only).
misl_overlay_migrate() {
  local q=$1 l new
  l=$(misl_overlay_legacy_dir "$q") || return 0
  [[ -f $l/applied ]] || return 0
  new=$(misl_overlay_state_root)/$q
  [[ -e $new/applied ]] && return 0
  mkdir -p "$(dirname "$new")"
  if [[ -d $new ]]; then
    mv "$l"/* "$new"/ && rmdir "$l"
  else
    mv "$l" "$new"
  fi
  info "migrated 0.3 stamp ${l##*/} -> $q"
}

misl_overlay_stamp() {
  local q dir
  q=$(misl_overlay_canon "$1") || exit 1
  dir=$(misl_overlay_state_root)/$q
  mkdir -p "$dir"
  {
    printf 'name=%s\n' "$q"
    printf 'when=%s\n' "$(date -u +%FT%TZ)"
  } >"$dir/applied"
  misl_overlay_write_os_release
}

misl_overlay_unstamp() {
  local q dir root
  q=$(misl_overlay_canon "$1") || exit 1
  root=$(misl_overlay_state_root)
  dir=$root/$q
  rm -f "$dir/applied" "$dir/owned"
  # Drop now-empty dirs up to the state root (keeps parents' stamps).
  while [[ $dir != "$root" && $dir == "$root"/* ]]; do
    rmdir "$dir" 2>/dev/null || break
    dir=${dir%/*}
  done
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

# Delete only paths listed in <state>/<qname>/owned (files and symlinks).
misl_overlay_undo_owned() {
  local q dest f path
  q=$(misl_overlay_canon "$1") || exit 1
  dest=$(misl_overlay_dest)
  f=$(misl_overlay_state_root)/$q/owned
  [[ -f $f ]] || return 0
  while IFS= read -r path || [[ -n $path ]]; do
    [[ -n $path ]] || continue
    if [[ -n $dest ]]; then
      path=${dest}${path}
    fi
    [[ $path == */ ]] && continue
    if [[ -L $path || -f $path ]]; then
      rm -f "$path"
      info "removed $path"
    fi
  done <"$f"
  # Directories (recorded with a trailing /): deepest first, only if empty.
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    path=${dest}${path%/}
    if [[ -d $path && ! -L $path ]] && rmdir "$path" 2>/dev/null; then
      info "removed dir $path"
    fi
  done < <(grep '/$' "$f" | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
}

# Copy overlays/<q>/files/ into the target, recording every file,
# symlink and newly created directory with misl_overlay_own, so undo
# restores the tree byte for byte. Refuses (before writing anything) to
# overwrite a path this overlay does not own unless MISL_FORCE=1.
# Call from apply.sh; q defaults to $MISL_OVERLAY_APPLYING.
misl_overlay_install_files() {
  local q=${1:-${MISL_OVERLAY_APPLYING:-}} src dest rel t owned clash=""
  [[ -n $q ]] || die "misl_overlay_install_files: no overlay"
  src=$(misl_overlay_home)/$q/files
  [[ -d $src ]] || return 0
  dest=$(misl_overlay_dest)
  owned=$(misl_overlay_state_root)/$q/owned
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    t=${dest}${rel}
    [[ -d $src$rel && ! -L $src$rel ]] && continue
    if [[ -e $t || -L $t ]]; then
      [[ -f $owned ]] && grep -qxF "$rel" "$owned" && continue
      clash+=" $t"
    fi
  done < <(cd "$src" && find . -mindepth 1 | sed 's|^\.||' | LC_ALL=C sort)
  if [[ -n $clash && ${MISL_FORCE:-0} != 1 ]]; then
    die "overlay $q: refusing to overwrite unowned:$clash (MISL_FORCE=1 to take them)"
  fi
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    t=${dest}${rel}
    if [[ -d $src$rel && ! -L $src$rel ]]; then
      if [[ ! -d $t ]]; then
        mkdir -m755 "$t"
        misl_overlay_own "$rel/"
      fi
      continue
    fi
    rm -f "$t"
    cp -P --preserve=mode "$src$rel" "$t"
    [[ -L $t ]] || chmod go-w "$t"
    misl_overlay_own "$rel"
    info "installed $t"
  done < <(cd "$src" && find . -mindepth 1 | sed 's|^\.||' | LC_ALL=C sort)
}

misl_overlay_active_qnames() {
  local q
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    misl_overlay_load "$q"
    if [[ -n ${LFS:-} ]] && misl_overlay_applied "$q" 2>/dev/null; then
      printf '%s\n' "$q"
    elif misl_overlay_is_default; then
      printf '%s\n' "$q"
    fi
  done <<<"$(misl_overlay_all)"
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

# Applied overlays that need $1: its children (any depth) and anything
# whose requires= names it.
misl_overlay_dependents_applied() {
  local target q req a
  target=$(misl_overlay_canon "$1") || exit 1
  while IFS= read -r q; do
    [[ -n $q && $q != "$target" ]] || continue
    misl_overlay_applied "$q" || continue
    a=" $(misl_overlay_ancestors "$q" | tr '\n' ' ') "
    if [[ $a == *" $target "* ]]; then
      printf '%s\n' "$q"
      continue
    fi
    misl_overlay_load "$q"
    for req in $OVERLAY_REQUIRES; do
      req=$(misl_overlay_canon "$req") || exit 1
      if [[ $req == "$target" ]]; then
        printf '%s\n' "$q"
        break
      fi
    done
  done <<<"$(misl_overlay_all)"
}

misl_overlay_applyable() {
  case ${1:-} in
    alpha|beta|rc|stable) return 0 ;;
    *) return 1 ;;
  esac
}

# Expand names: ancestors first, then requires=, then the overlay.
# Die on stub/missing/ambiguous. Default overlays are the base: skipped.
misl_overlay_resolve() {
  local n out=() seen=" "
  _ov_add() {
    local x=$1 via=${2:-} a deps
    x=$(misl_overlay_canon "$x") || exit 1
    [[ $seen == *" $x "* ]] && return 0
    misl_overlay_load "$x"
    if misl_overlay_is_default; then
      seen+=" $x "
      return 0
    fi
    if ! misl_overlay_applyable "$OVERLAY_STATUS"; then
      if [[ -n $via ]]; then
        die "cannot apply $via: $x is $OVERLAY_STATUS (apply: alpha|beta|rc|stable)"
      fi
      die "overlay $x is $OVERLAY_STATUS (apply: alpha|beta|rc|stable)"
    fi
    deps="$(misl_overlay_ancestors "$x" | tr '\n' ' ') $OVERLAY_REQUIRES"
    for a in $deps; do
      _ov_add "$a" "${via:-$x}"
    done
    seen+=" $x "
    out+=("$x")
  }
  for n in "$@"; do
    _ov_add "$n"
  done
  (( ${#out[@]} )) && printf '%s\n' "${out[@]}"
  return 0
}

misl_overlay_list() {
  local header=1 q mark pri t
  case ${1:-} in
    --header|-H) header=1 ;;
    --no-header) header=0 ;;
  esac
  {
    [[ $header == 1 ]] && printf '%s\t%s\t%s\t%s\t%s\n' NAME STATUS ON CLASS TITLE
    while IFS= read -r q; do
      [[ -n $q ]] || continue
      misl_overlay_load "$q"
      pri=${OVERLAY_PRIORITY:-100}
      mark=off
      if [[ -n ${LFS:-} ]] && misl_overlay_applied "$q" 2>/dev/null; then
        mark=on
      elif misl_overlay_is_default; then
        mark=default
      fi
      t=$OVERLAY_TITLE
      misl_overlay_is_oneway "$q" && t+=" [one-way]"
      printf '%04d\t%s\t%s\t%s\t%s\t%s\n' "$pri" "$q" "$OVERLAY_STATUS" "$mark" "$OVERLAY_CLASS" "$t"
    done <<<"$(misl_overlay_all)" | sort -n -k1,1 -k2,2 | cut -f2-
  } | misl_table
}

misl_overlay_status() {
  require_lfs_set
  local q any=0 st l ow
  st=$(misl_overlay_state_root)
  printf 'LFS=%s\n' "$LFS"
  printf 'applied:\n'
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    if [[ -f $st/$q/applied ]]; then
      any=1
      ow=
      misl_overlay_is_oneway "$q" && ow=" one-way: ./misl reset to take it back"
      printf '  %s  (%s)%s\n' "$q" "$(tr '\n' ' ' <"$st/$q/applied")" "$ow"
    elif l=$(misl_overlay_legacy_dir "$q") && [[ -f $l/applied ]]; then
      any=1
      printf '  %s  (0.3 stamp %s; moves on next apply/undo)\n' "$q" "${l#"$st"/}"
    fi
  done <<<"$(misl_overlay_all)"
  if [[ $any -eq 0 ]]; then
    printf '  (none)\n'
  fi
  if declare -F misl_fw_status >/dev/null; then
    misl_fw_status
  fi
  if declare -F misl_reset_have >/dev/null; then
    if misl_reset_have; then
      printf 'reset snapshot: yes (./misl reset --info)\n'
    else
      printf 'reset snapshot: none\n'
    fi
  fi
}

misl_overlay_run_hook() {
  local q=$1 hook=$2
  local f
  f=$(misl_overlay_home)/$q/$hook
  [[ -f $f ]] || return 0
  # shellcheck disable=SC1090
  . "$f"
}

misl_overlay_apply_one() {
  local q
  q=$(misl_overlay_canon "$1") || exit 1
  misl_overlay_load "$q"
  misl_overlay_migrate "$q"
  if misl_overlay_applied "$q"; then
    info "overlay $q already applied"
    return 0
  fi
  info "overlay apply $q ($OVERLAY_TITLE)"
  # firmware.list first: it checks everything before writing anything.
  if declare -F misl_fw_apply >/dev/null; then misl_fw_apply "$q"; fi
  MISL_OVERLAY_APPLYING=$q
  export MISL_OVERLAY_APPLYING
  misl_overlay_run_hook "$q" apply.sh
  unset MISL_OVERLAY_APPLYING
  misl_overlay_stamp "$q"
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
  names=$(misl_overlay_resolve "$@") || exit 1
  # Before anything is written: the base snapshot misl reset restores.
  if [[ -n $names ]] && declare -F misl_reset_snapshot_take >/dev/null; then
    misl_reset_snapshot_take
  fi
  local shown=" "
  while IFS= read -r n; do
    [[ -n $n ]] || continue
    misl_overlay_applied "$n" && continue
    misl_overlay_is_oneway "$n" || continue
    [[ $shown == *" ${n%%/*} "* ]] && continue
    shown+="${n%%/*} "
    misl_overlay_oneway_notice "$n"
  done <<<"$names"
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

misl_overlay_oneway_refuse() {
  local q=$1 why="it edits files in place and misl has no exact record of the old contents."
  if declare -F "misl_${q%%/*}_oneway_why" >/dev/null; then
    why=$("misl_${q%%/*}_oneway_why")
  fi
  die "overlay $q is one-way and cannot be undone: $why To go back to the base tree run ./misl reset (restores the snapshot taken before the first overlay apply; see ./misl reset --info) or rebuild."
}

misl_overlay_undo_one() {
  local q dep
  q=$(misl_overlay_canon "$1") || exit 1
  misl_overlay_load "$q"
  if misl_overlay_is_default; then
    die "overlay $q is the default (the base tree). not undone"
  fi
  if misl_overlay_is_oneway "$q"; then
    misl_overlay_oneway_refuse "$q"
  fi
  misl_overlay_migrate "$q"
  dep=$(misl_overlay_dependents_applied "$q" | tr '\n' ' ')
  if [[ -n ${dep// /} ]]; then
    die "undo $q blocked: still applied: $dep(undo children first)"
  fi
  info "overlay undo $q"
  misl_overlay_undo_owned "$q"
  if declare -F misl_fw_undo >/dev/null; then misl_fw_undo "$q"; fi
  misl_overlay_run_hook "$q" undo.sh || true
  misl_overlay_unstamp "$q"
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

# Kernel extras: any applied overlay with kernel=1 (stamps), or
# MISL_CLOUD=1 for one rebuild without applying cloud.
misl_overlay_kernel_wanted() {
  [[ ${MISL_CLOUD:-0} == 1 ]] && return 0
  local q
  local LFS=${LFS:-/}
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    misl_overlay_applied "$q" || continue
    misl_overlay_load "$q"
    [[ ${OVERLAY_KERNEL:-0} == 1 ]] && return 0
  done <<<"$(misl_overlay_all)"
  return 1
}

# kernel.list: one option per line. Blank lines and # comments are
# ignored; whitespace is trimmed. CONFIG_ is optional.
#   CONFIG_X | X | X=y   built in      X=m   module      X=n   off
#   X="str"   string      X=123 | X=-1 | X=0x1f   int / hex
# Requests are TAB records: SYM VALUE ORIGIN, VALUE one of y m n
# "str" or a number, ORIGIN <qname> (<file>:<line>).

# Parse one file; die on a malformed line naming file:line.
misl_kernel_list_parse() {
  local f=$1 origin=${2:-$1} line sym val n=0
  [[ -f $f ]] || die "kernel.list: no file $f"
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    [[ $line != *\"* ]] && line=${line%%#*}
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z $line || $line == \#* ]] && continue
    if [[ $line =~ ^(CONFIG_)?([A-Za-z0-9_]+)[[:space:]]*(=[[:space:]]*(.*))?$ ]]; then
      sym=CONFIG_${BASH_REMATCH[2]}
      val=${BASH_REMATCH[4]:-y}
      [[ -n ${BASH_REMATCH[3]} && -z ${BASH_REMATCH[4]} ]] && \
        die "kernel.list $f:$n: empty value: $line"
    else
      die "kernel.list $f:$n: malformed: $line"
    fi
    if [[ $val =~ ^\"([^\"]*)\"([[:space:]]+#.*)?$ ]]; then
      val="\"${BASH_REMATCH[1]}\""
    elif [[ $val =~ ^(y|m|n|-?[0-9]+|0[xX][0-9A-Fa-f]+)$ ]]; then
      :
    else
      die "kernel.list $f:$n: bad value for $sym: $val (y|m|n|\"str\"|number|0xhex)"
    fi
    printf '%s\t%s\t%s\n' "$sym" "$val" "$origin ($f:$n)"
  done <"$f"
}

# Requests from every applied overlay's kernel.list, in apply order
# (qname order: ancestors first). Later overlay wins; a different value
# from an earlier overlay warns. Output: one record per symbol.
misl_kernel_list_requests() {
  local q f recs="" sym val org osym oval oorg merged=""
  local LFS=${LFS:-/}
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    f=$(misl_overlay_home)/$q/kernel.list
    [[ -f $f ]] || continue
    misl_overlay_applied "$q" || continue
    recs+=$(misl_kernel_list_parse "$f" "$q") || exit 1
    recs+=$'\n'
  done <<<"$(misl_overlay_all)"
  while IFS=$'\t' read -r sym val org; do
    [[ -n $sym ]] || continue
    local kept=""
    while IFS=$'\t' read -r osym oval oorg; do
      [[ -n $osym ]] || continue
      if [[ $osym == "$sym" ]]; then
        [[ $oval != "$val" ]] && warn "kernel.list: $sym=$oval from $oorg overridden by $sym=$val from $org"
        continue
      fi
      kept+=$osym$'\t'$oval$'\t'$oorg$'\n'
    done <<<"$merged"
    merged=$kept$sym$'\t'$val$'\t'$org$'\n'
  done <<<"$recs"
  printf '%s' "$merged"
}

# Apply records (stdin) with a scripts/config command: "$@" --enable X ...
misl_kernel_list_apply() {
  local sym val org
  while IFS=$'\t' read -r sym val org; do
    [[ -n $sym ]] || continue
    case $val in
      y) "$@" --enable "$sym" ;;
      m) "$@" --module "$sym" ;;
      n) "$@" --disable "$sym" ;;
      \"*) val=${val#\"}; "$@" --set-str "$sym" "${val%\"}" ;;
      *) "$@" --set-val "$sym" "$val" ;;
    esac || die "kernel.list: scripts/config failed on $sym=$val ($org)"
  done
}

# Verify records (stdin) against a .config after the final olddefconfig.
# Fails naming option, wanted, actual and origin. MISL_KERNEL_LIST_LAX=1
# turns failures into warnings.
misl_kernel_list_verify() {
  local cfg=$1 sym val org line have bad=0 want
  [[ -f $cfg ]] || die "kernel.list verify: no $cfg"
  while IFS=$'\t' read -r sym val org; do
    [[ -n $sym ]] || continue
    line=$(grep -E "^(${sym}=|# ${sym} is not set$)" "$cfg" | tail -n1 || true)
    case $line in
      "$sym="*) have=${line#*=} ;;
      *) have=n ;;
    esac
    want=$val
    if [[ $val =~ ^0[xX] && $have =~ ^0[xX] ]]; then
      want=${val,,}; have=${have,,}
    fi
    [[ $have == "$want" ]] && continue
    bad=$((bad + 1))
    if [[ ${MISL_KERNEL_LIST_LAX:-0} == 1 ]]; then
      warn "kernel.list: $sym wanted $val, .config has ${line:-nothing} (from $org)"
    else
      misllog ERROR "kernel.list: $sym wanted $val, .config has ${line:-nothing} (from $org)" >&2
    fi
  done
  if (( bad )) && [[ ${MISL_KERNEL_LIST_LAX:-0} != 1 ]]; then
    die "kernel.list: $bad option(s) did not stick after olddefconfig (missing deps or renamed symbols; MISL_KERNEL_LIST_LAX=1 to warn only)"
  fi
  return 0
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
      printf '%s\n' "usage: misl overlay list [--header|--no-header]|status|apply <name...>|undo <name...>|install cloud" \
        "  <name> is a qualified name (cloud/do, desktop/asus/rog-strix-x570)" \
        "  or a unique leaf (do). apply pulls missing parents first;" \
        "  undo children before parents. terminal is the base: not undone." \
        "  one-way overlays (cloud and its children) cannot be undone:" \
        "  ./misl reset puts the whole tree back to the pre-overlay base."
      ;;
    *) die "usage: misl overlay list|status|apply|undo|install" ;;
  esac
}
