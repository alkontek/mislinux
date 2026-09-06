# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Firmware from the staged linux-firmware tree (10-boot/linux-firmware,
# /usr/share/misl/linux-firmware) into /usr/lib/firmware (= /lib/firmware,
# merged-usr), only what an applied overlay's firmware.list names.
#
# State, under var/lib/misl/:
#   overlays/<qname>/firmware.files   paths this overlay wrote or shares
#                                     ("f|l|d<TAB>/usr/lib/firmware/...")
#   firmware/owners                   "<path><TAB><qname>" per owner
# A path is removed when its last owner is undone. Never fetches.

MISL_FW_STAGE=/usr/share/misl/linux-firmware
MISL_FW_DEST=/usr/lib/firmware

misl_fw_dest_root() { misl_overlay_dest; }
misl_fw_stage() { printf '%s%s\n' "$(misl_fw_dest_root)" "$MISL_FW_STAGE"; }
misl_fw_owners() { printf '%s/firmware/owners\n' "$(misl_overlay_state_root | sed 's|/overlays$||')"; }
misl_fw_files() { printf '%s/%s/firmware.files\n' "$(misl_overlay_state_root)" "$1"; }

# firmware.list: one path or glob per line, relative to the staged tree;
# "#" comments, blank lines. Prints "<lineno><TAB><pattern>".
misl_fw_list_parse() {
  local f=$1 line n=0 tok
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%%#*}
    for tok in $line; do
      if [[ $tok == /* || $tok == *..* || ! $tok =~ ^[][A-Za-z0-9_.,+@=*?/-]+$ ]]; then
        die "$f:$n: bad firmware path '$tok' (relative to $MISL_FW_STAGE, no '..')"
      fi
      printf '%s\t%s\n' "$n" "${tok%/}"
    done
  done <"$f"
}

misl_fw_staged_version() {
  local s
  s=$(misl_fw_stage)
  [[ -f $s/.misl-version ]] || return 1
  cat "$s/.misl-version"
}

# Expand one pattern in the staged tree: a file, symlink, directory
# (recursive), or glob; also tries the .xz / .zst variant copy-firmware
# may have staged. Prints staged-relative paths (files and symlinks).
misl_fw_expand() {
  local stage=$1 pat=$2 m sfx hit=0
  (
    cd "$stage" || exit 1
    shopt -s nullglob dotglob
    for sfx in "" .xz .zst; do
      # shellcheck disable=SC2206
      local ms=($pat$sfx)
      for m in "${ms[@]}"; do
        if [[ -d $m && ! -L $m ]]; then
          find "$m" \( -type f -o -type l \) ! -name '.*' -print
        elif [[ -e $m || -L $m ]]; then
          printf '%s\n' "$m"
        else
          continue   # a literal (non-glob) word that did not exist
        fi
        hit=1
      done
      [[ $hit == 1 ]] && break
    done
    true
  ) | sort -u
}

# Add symlink targets (WHENCE Link: entries are symlinks in the staged
# tree) so no link lands dangling. Input/output: staged-relative paths.
misl_fw_close_links() {
  local stage=$1 p t d
  local -A seen=()
  local queue=()
  while IFS= read -r p; do [[ -n $p ]] && queue+=("$p"); done
  while ((${#queue[@]})); do
    p=${queue[0]}; queue=("${queue[@]:1}")
    [[ -z ${seen[$p]:-} ]] || continue
    seen[$p]=1
    printf '%s\n' "$p"
    if [[ -L $stage/$p ]]; then
      t=$(readlink "$stage/$p")
      [[ $t == /* ]] && die "staged firmware link $p -> $t is absolute"
      d=$(dirname "$p")
      t=$(realpath -m --relative-to="$stage" "$stage/$d/$t")
      [[ $t == ../* ]] && die "staged firmware link $p escapes the tree"
      if [[ -d $stage/$t && ! -L $stage/$t ]]; then
        while IFS= read -r d; do queue+=("$d"); done < <(cd "$stage" && find "$t" \( -type f -o -type l \) -print)
      else
        queue+=("$t")
      fi
    fi
  done
}

# Resolve an overlay's list. Prints staged-relative paths; dies (or warns
# with MISL_FIRMWARE_LAX=1) naming file:line for patterns with no match.
misl_fw_resolve() {
  local q=$1 f stage n pat out miss=0
  f=$(misl_overlay_home)/$q/firmware.list
  [[ -f $f ]] || return 0
  stage=$(misl_fw_stage)
  misl_fw_staged_version >/dev/null || \
    die "overlay $q has firmware.list but linux-firmware is not staged at $stage (build 10-boot/linux-firmware first, then apply)"
  local parsed
  parsed=$(misl_fw_list_parse "$f") || exit 1
  {
    while IFS=$'\t' read -r n pat; do
      [[ -n $pat ]] || continue
      out=$(misl_fw_expand "$stage" "$pat")
      if [[ -z $out ]]; then
        if [[ ${MISL_FIRMWARE_LAX:-0} == 1 ]]; then
          warn "$f:$n: '$pat' not in staged linux-firmware $(misl_fw_staged_version) (MISL_FIRMWARE_LAX=1: skipped)"
        else
          printf 'FWMISS\t%s:%s: %s\n' "$f" "$n" "$pat"
          miss=1
        fi
        continue
      fi
      printf '%s\n' "$out"
    done <<<"$parsed"
  } >"${TMPDIR:-/tmp}/misl-fw.$$"
  if grep -q '^FWMISS' "${TMPDIR:-/tmp}/misl-fw.$$"; then
    sed -n 's/^FWMISS\t/  /p' "${TMPDIR:-/tmp}/misl-fw.$$" >&2
    rm -f "${TMPDIR:-/tmp}/misl-fw.$$"
    die "overlay $q: firmware.list entries not in staged linux-firmware $(misl_fw_staged_version) (never fetched; MISL_FIRMWARE_LAX=1 to skip)"
  fi
  sort -u "${TMPDIR:-/tmp}/misl-fw.$$" | misl_fw_close_links "$stage" | sort -u
  rm -f "${TMPDIR:-/tmp}/misl-fw.$$"
  [[ $miss == 0 ]]
}

misl_fw_has_owner() { [[ -f $1 ]] && grep -qP "^\Q$2\E\t" "$1"; }

# Apply: called by misl_overlay_apply_one before apply.sh.
misl_fw_apply() {
  local q=$1 stage root owners files list rel dst d p kind created
  [[ -f $(misl_overlay_home)/$q/firmware.list ]] || return 0
  stage=$(misl_fw_stage)
  root=$(misl_fw_dest_root)
  list=$(misl_fw_resolve "$q") || exit 1
  owners=$(misl_fw_owners)
  files=$(misl_fw_files "$q")
  mkdir -p "$(dirname "$owners")" "$(dirname "$files")"
  touch "$owners"
  # Check everything before writing anything.
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    p=$MISL_FW_DEST/$rel
    dst=$root$p
    if [[ -e $dst || -L $dst ]] && ! misl_fw_has_owner "$owners" "$p"; then
      if [[ ${MISL_FORCE:-0} == 1 ]]; then
        warn "$p exists, not misl's: overwritten and owned by $q (MISL_FORCE=1)"
      else
        die "refusing to overwrite $p (not installed by a misl overlay; MISL_FORCE=1)"
      fi
    fi
  done <<<"$list"
  local nf=0 nl=0 nd=0
  : >>"$files"
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    p=$MISL_FW_DEST/$rel
    dst=$root$p
    # Parent dirs this apply creates (recorded for undo; deepest last).
    # A dir another overlay created is shared (co-owned) the same way.
    created=()
    d=$(dirname "$p")
    while [[ $d != "$MISL_FW_DEST" ]]; do
      if [[ ! -d $root$d ]] || misl_fw_has_owner "$owners" "$d"; then
        created=("$d" "${created[@]}")
      fi
      d=$(dirname "$d")
    done
    for d in "${created[@]}"; do
      [[ -d $root$d ]] || { mkdir "$root$d"; nd=$((nd + 1)); }
      grep -qxF "d"$'\t'"$d" "$files" || printf 'd\t%s\n' "$d" >>"$files"
      grep -qxF "$d"$'\t'"$q" "$owners" || printf '%s\t%s\n' "$d" "$q" >>"$owners"
    done
    if [[ -L $stage/$rel ]]; then kind=l; nl=$((nl + 1)); else kind=f; nf=$((nf + 1)); fi
    if ! misl_fw_has_owner "$owners" "$p" || [[ ! -e $dst && ! -L $dst ]]; then
      rm -f "$dst"
      cp -P --preserve=mode,timestamps "$stage/$rel" "$dst"
    fi
    grep -qxF "$kind"$'\t'"$p" "$files" || printf '%s\t%s\n' "$kind" "$p" >>"$files"
    grep -qxF "$p"$'\t'"$q" "$owners" || printf '%s\t%s\n' "$p" "$q" >>"$owners"
  done <<<"$list"
  # Dirs that already existed but are shared: owned via their files.
  info "firmware $q: $nf files, $nl links, $nd dirs into $MISL_FW_DEST (linux-firmware $(misl_fw_staged_version))"
}

# Undo: drop q as an owner; delete paths with no owner left, files and
# links first, then dirs deepest-first if empty.
misl_fw_undo() {
  local q=$1 owners files kind p root left
  files=$(misl_fw_files "$q")
  [[ -f $files ]] || return 0
  owners=$(misl_fw_owners)
  root=$(misl_fw_dest_root)
  if [[ -f $owners ]]; then
    awk -F'\t' -v q="$q" '$2 != q' "$owners" >"$owners.new"
    mv "$owners.new" "$owners"
  fi
  local n=0 kept=0
  while IFS=$'\t' read -r kind p; do
    [[ $kind == f || $kind == l ]] || continue
    if misl_fw_has_owner "$owners" "$p"; then kept=$((kept + 1)); continue; fi
    rm -f "$root$p" && n=$((n + 1))
  done <"$files"
  while IFS=$'\t' read -r kind p; do
    [[ $kind == d ]] || continue
    misl_fw_has_owner "$owners" "$p" && continue
    rmdir "$root$p" 2>/dev/null || warn "kept non-empty $p"
  done < <(grep -P '^d\t' "$files" | sort -t$'\t' -k2,2r)
  rm -f "$files"
  left=$(wc -l <"$owners" 2>/dev/null || echo 0)
  if [[ -f $owners && $left == 0 ]]; then
    rm -f "$owners"
    rmdir "$(dirname "$owners")" 2>/dev/null || true
  fi
  info "firmware $q: removed $n, kept $kept still owned by other overlays"
}

misl_fw_status() {
  require_lfs_set
  local v q files
  v=$(misl_fw_staged_version) || v="not staged ($(misl_fw_stage))"
  printf 'linux-firmware staged: %s\n' "$v"
  printf 'installed into %s by overlays:\n' "$MISL_FW_DEST"
  local any=0
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    files=$(misl_fw_files "$q")
    if [[ -f $files ]]; then
      any=1
      printf '  %-32s %s files, %s links, %s dirs\n' "$q" \
        "$(grep -c '^f' "$files")" "$(grep -c '^l' "$files")" "$(grep -c '^d' "$files")"
    elif [[ -f $(misl_overlay_home)/$q/firmware.list ]]; then
      printf '  %-32s has firmware.list, %s\n' "$q" \
        "$(misl_overlay_applied "$q" && echo 'applied without firmware (re-apply)' || echo 'not applied')"
    fi
  done <<<"$(misl_overlay_all)"
  [[ $any == 1 ]] || printf '  (none)\n'
}

# list <q>: what firmware.list resolves to now, and what is installed.
misl_fw_list() {
  require_lfs_set
  local q root rel p files state
  [[ $# -eq 1 ]] || die "usage: misl firmware list <overlay>"
  q=$(misl_overlay_canon "$1") || exit 1
  [[ -f $(misl_overlay_home)/$q/firmware.list ]] || { printf '%s: no firmware.list\n' "$q"; return 0; }
  root=$(misl_fw_dest_root)
  files=$(misl_fw_files "$q")
  MISL_FIRMWARE_LAX=1 misl_fw_resolve "$q" | while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    p=$MISL_FW_DEST/$rel
    if [[ -f $files ]] && grep -qP "^[fl]\t\Q$p\E$" "$files"; then state=installed
    elif [[ -e $root$p || -L $root$p ]]; then state=present-unowned
    else state=staged; fi
    printf '%-16s %s\n' "$state" "$p"
  done
}

misl_firmware() {
  local sub=${1:-status}
  shift || true
  case $sub in
    status) misl_fw_status ;;
    list) misl_fw_list "$@" ;;
    -h|--help|help) printf '%s\n' "usage: misl firmware status | list <overlay>" ;;
    *) die "usage: misl firmware status | list <overlay>" ;;
  esac
}
