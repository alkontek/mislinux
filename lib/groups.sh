# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Package groups. Every packages.manifest row carries exactly one
# group=<name> in its notes (one group per package). A missing group=,
# a comma list, a second group= or an undeclared name is an error
# (misl_groups_check_manifest, run before any selection).
# Declared groups (same list in the packages.manifest header):
#   base  toolchain + core system every image needs (always selected)
#   hw    physical hardware userland: PCI/USB ids and tools, ethtool,
#         audio, sensors
#   wifi  Wi-Fi userland: libnl, wpa_supplicant, iw, wireless-regdb
#   bluetooth  Bluetooth userland: bluez (glib is base)
#   lisp  SBCL Common Lisp
#   cloud cloud-init and its Python wheels (incoming/ only, no
#         packages.manifest rows)
# Optional groups selected, unioned:
#   1. MISL_GROUPS="hw lisp" (comma or space; all = every group)
#   2. packages= of the target overlays plus their ancestors and
#      requires=. Targets: MISL_TARGET_OVERLAYS="desktop/asus/rog-strix-x570"
#      if set, else applied + default overlays on $LFS.
#   3. Neither MISL_GROUPS nor MISL_TARGET_OVERLAYS set: also the
#      selection `sources stage` recorded in $LFS/var/lib/misl/groups,
#      so build-stage in the chroot builds what was staged.
# No process substitution here (no /dev/fd in some workspaces).

MISL_GROUPS_ALWAYS="base"
MISL_GROUPS_DEFINED="base hw wifi bluetooth lisp cloud"
misl_group_meaning() {
  case $1 in
    base) echo "toolchain + core system every image needs" ;;
    hw) echo "physical hardware userland: PCI/USB tools, ethtool, audio, sensors" ;;
    wifi) echo "Wi-Fi userland: libnl, wpa_supplicant, iw, wireless-regdb" ;;
    bluetooth) echo "Bluetooth userland: bluez (glib is base)" ;;
    lisp) echo "SBCL Common Lisp" ;;
    cloud) echo "cloud-init and its Python wheels (incoming/)" ;;
  esac
}

unset MISL_GROUPS_SEL

misl_groups_record_file() {
  local root=${LFS:-}
  [[ -n $root ]] || return 1
  printf '%s/var/lib/misl/groups\n' "${root%/}"
}

# Words of a comma/space list, one per line.
_misl_groups_words() {
  local w
  for w in ${1//,/ }; do
    [[ -n $w ]] && printf '%s\n' "$w"
  done
  return 0
}

# The one group= of a notes string. Prints nothing when absent.
# Returns 2 (and prints nothing) for more than one group.
misl_groups_of_notes() {
  local n g="" c=0
  for n in $1; do
    [[ $n == group=* ]] || continue
    c=$((c + 1))
    g=${n#group=}
  done
  if (( c > 1 )) || [[ $g == *,* ]]; then
    return 2
  fi
  [[ -n $g ]] && printf '%s\n' "$g"
  return 0
}

# Validate the manifest: exactly one declared group per row. Dies
# listing every bad row as file:line. Cached per manifest path.
misl_groups_check_manifest() {
  local man line stage name ver tarball patches notes g bad="" ln=0
  man=$(misl_manifest_file)
  [[ -f $man ]] || return 0
  [[ ${MISL_GROUPS_CHECKED:-} == "$man" ]] && return 0
  while IFS= read -r line || [[ -n $line ]]; do
    ln=$((ln + 1))
    read -r stage name ver tarball patches notes <<<"$line"
    [[ -z ${stage:-} || $stage == \#* ]] && continue
    if ! g=$(misl_groups_of_notes "${notes:-}"); then
      bad+=$'\n'"  $man:$ln: $stage/$name: more than one group (one group per package)"
    elif [[ -z $g ]]; then
      bad+=$'\n'"  $man:$ln: $stage/$name: no group= (every row needs one)"
    elif [[ " $MISL_GROUPS_DEFINED " != *" $g "* ]]; then
      bad+=$'\n'"  $man:$ln: $stage/$name: unknown group=$g (declared: $MISL_GROUPS_DEFINED)"
    fi
  done <"$man"
  [[ -z $bad ]] || die "packages.manifest groups:$bad"
  MISL_GROUPS_CHECKED=$man
}

# Every declared group, in order.
misl_groups_known() {
  _misl_groups_words "$MISL_GROUPS_DEFINED"
}

# Overlays whose packages= count, with ancestors and requires=.
misl_groups_target_overlays() {
  local list q todo=() seen=" " r a
  declare -F misl_overlay_canon >/dev/null || return 0
  if [[ -n ${MISL_TARGET_OVERLAYS:-} ]]; then
    list=$(_misl_groups_words "$MISL_TARGET_OVERLAYS")
  else
    list=$(misl_overlay_active_qnames 2>/dev/null || true)
  fi
  while IFS= read -r q; do
    [[ -n $q ]] || continue
    q=$(misl_overlay_canon "$q") || die "MISL_TARGET_OVERLAYS: unknown overlay $q"
    todo+=("$q")
  done <<<"$list"
  while (( ${#todo[@]} )); do
    q=${todo[0]}
    todo=("${todo[@]:1}")
    [[ $seen == *" $q "* ]] && continue
    seen+="$q "
    printf '%s\n' "$q"
    while IFS= read -r a; do
      [[ -n $a ]] && todo+=("$a")
    done <<<"$(misl_overlay_ancestors "$q")"
    misl_overlay_load "$q"
    for r in ${OVERLAY_REQUIRES//,/ }; do
      r=$(misl_overlay_canon "$r") || continue
      todo+=("$r")
    done
  done
}

# Selected groups, sorted, one per line. "all" alone means every group.
misl_groups_selected() {
  local q rec
  {
    _misl_groups_words "${MISL_GROUPS:-}"
    while IFS= read -r q; do
      [[ -n $q ]] || continue
      misl_overlay_load "$q"
      _misl_groups_words "${OVERLAY_PACKAGES:-}"
    done <<<"$(misl_groups_target_overlays)"
    if [[ -z ${MISL_GROUPS:-} && -z ${MISL_TARGET_OVERLAYS:-} ]] && \
       rec=$(misl_groups_record_file) && [[ -f $rec ]]; then
      _misl_groups_words "$(cat "$rec")"
    fi
  } | awk -v a=" $MISL_GROUPS_ALWAYS " 'index(a, " " $0 " ") == 0' | LC_ALL=C sort -u | {
    local all=0 g out=()
    while IFS= read -r g; do
      [[ $g == all ]] && all=1
      out+=("$g")
    done
    if (( all )); then
      printf 'all\n'
    elif (( ${#out[@]} )); then
      printf '%s\n' "${out[@]}"
    fi
  }
}

# Cache for loops: MISL_GROUPS_SEL=" g1 g2 " (or " all ").
misl_groups_prepare() {
  misl_groups_check_manifest
  local g
  for g in $(_misl_groups_words "${MISL_GROUPS:-}"); do
    [[ $g == all || " $MISL_GROUPS_DEFINED " == *" $g "* ]] || die "MISL_GROUPS: unknown group $g (declared: $MISL_GROUPS_DEFINED)"
  done
  MISL_GROUPS_SEL=" $(misl_groups_selected | tr '\n' ' ')"
}

_misl_groups_sel() {
  [[ -n ${MISL_GROUPS_SEL:-} ]] || misl_groups_prepare
  printf '%s\n' "$MISL_GROUPS_SEL"
}

misl_group_selected() {
  local g=$1 sel
  [[ " $MISL_GROUPS_ALWAYS " == *" $g "* ]] && return 0
  [[ -n ${MISL_GROUPS_SEL:-} ]] || misl_groups_prepare
  sel=$MISL_GROUPS_SEL
  [[ $sel == *" all "* || $sel == *" $g "* ]]
}

# Row notes -> wanted? (manifest validated first: one group per row)
misl_group_notes_wanted() {
  local g
  misl_groups_check_manifest
  g=$(misl_groups_of_notes "$1") || die "more than one group in: $1"
  [[ -n $g ]] || die "no group= in: $1"
  misl_group_selected "$g"
}

# Tarball (wget-list name) wanted? Wanted unless every manifest row
# that uses it is in unselected groups. Not in the manifest = wanted.
misl_group_tarball_wanted() {
  local want=$1 man stage name ver tarball patches notes seen=0
  man=$(misl_manifest_file)
  [[ -f $man ]] || return 0
  while read -r stage name ver tarball patches notes; do
    [[ -z ${stage:-} || $stage == \#* ]] && continue
    [[ $tarball == "$want" || " ${patches//,/ } " == *" $want "* ]] || continue
    seen=1
    misl_group_notes_wanted "${notes:-}" && return 0
  done <"$man"
  (( seen == 0 ))
}

# Manifest row group label for messages.
misl_group_label() {
  local g
  g=$(misl_groups_of_notes "$1") || g=INVALID
  printf '%s\n' "${g:-NONE}"
}

misl_groups_record() {
  local f
  f=$(misl_groups_record_file) || return 0
  mkdir -p "$(dirname "$f")"
  misl_groups_selected | paste -sd' ' - >"$f"
  info "groups recorded in $f: $(cat "$f")"
}

# ---- incoming/ files tied to a group (config/incoming.manifest) ----
# Columns: group name version file md5 notes...
#   md5: md5sums when the mirror lists the file, else ${md5env} when
#   notes has md5env=VAR and it is set, else the md5 column, else
#   none (`-`: warn). Fetched from $MISL_MIRROR/incoming/ only, to
#   $MISL_SNAPSHOT/incoming, staged into SOURCES. file is a path under
#   incoming/ (wheels/<name>.whl), kept as-is in the snapshot and SOURCES.
#   notes: kind=wheel|tarball|binary, md5env=VAR.

misl_incoming_manifest() {
  printf '%s\n' "${MISL_INCOMING_MANIFEST:-$MISL_ROOT/config/incoming.manifest}"
}

# Value of key=VALUE in a notes string.
_misl_incoming_note() {
  local key=$1 n
  for n in $2; do
    [[ $n == "$key"=* ]] && { printf '%s\n' "${n#"$key"=}"; return 0; }
  done
  return 1
}

# Prints group<TAB>file<TAB>md5<TAB>md5env<TAB>kind, one row per file.
# With $1: rows of that group only (selected or not); else rows of the
# selected groups. Dies on a row without a declared group.
misl_incoming_wanted() {
  local only=${1:-} man group name ver file md5 notes md5env kind ln=0
  man=$(misl_incoming_manifest)
  [[ -f $man ]] || return 0
  while read -r group name ver file md5 notes; do
    ln=$((ln + 1))
    [[ -z ${group:-} || $group == \#* ]] && continue
    [[ -n ${file:-} && -n ${ver:-} && -n ${name:-} ]] || die "$man:$ln: needs group name version file md5"
    [[ $file != /* && $file != *..* ]] || die "$man:$ln: file must be a path under incoming/: $file"
    [[ " $MISL_GROUPS_DEFINED " == *" $group "* ]] || die "$man:$ln: unknown group $group (declared: $MISL_GROUPS_DEFINED)"
    if [[ -n $only ]]; then
      [[ $group == "$only" ]] || continue
    else
      misl_group_selected "$group" || continue
    fi
    md5env=$(_misl_incoming_note md5env "${notes:-}") || md5env=-
    kind=$(_misl_incoming_note kind "${notes:-}") || kind=tarball
    printf '%s\t%s\t%s\t%s\t%s\n' "$group" "$file" "${md5:--}" "$md5env" "$kind"
  done <"$man"
}

# md5 for an incoming file. 1 when none is known.
misl_incoming_md5() {
  local file=$1 md5=$2 md5env=$3 m
  if [[ -f ${MISL_MD5SUMS:-} ]] && m=$(misl_md5_for "$(basename "$file")" 2>/dev/null); then
    printf '%s\n' "$m"; return 0
  fi
  if [[ $md5env != - && -n ${!md5env:-} ]]; then
    printf '%s\n' "${!md5env}"; return 0
  fi
  if [[ $md5 != - ]]; then
    printf '%s\n' "$md5"; return 0
  fi
  return 1
}

misl_incoming_dir() { printf '%s/incoming\n' "${MISL_SNAPSHOT:?}"; }

# $1: group (optional; default selected groups).
misl_incoming_fetch() {
  local tmp group file md5 md5env kind
  tmp=$(mktemp)
  misl_incoming_wanted "${1:-}" >"$tmp"
  while IFS=$'\t' read -r group file md5 md5env kind; do
    mkdir -p "$(misl_incoming_dir)"
    info "incoming ($group) $file"
    misl_fetch_one "${MISL_MIRROR:?}/incoming/$file" "$(misl_incoming_dir)/$file"
  done <"$tmp"
  rm -f "$tmp"
}

# 0 ok, 1 missing/mismatch. No md5 anywhere: warn, still ok.
misl_incoming_check() {
  local tmp group file md5 md5env kind path want got bad=0 hint
  tmp=$(mktemp)
  misl_incoming_wanted "${1:-}" >"$tmp"
  while IFS=$'\t' read -r group file md5 md5env kind; do
    path=$(misl_incoming_dir)/$file
    if [[ ! -f $path ]]; then
      warn "MISSING incoming ($group) $file"; bad=1; continue
    fi
    if want=$(misl_incoming_md5 "$file" "$md5" "$md5env"); then
      got=$(md5sum "$path" | awk '{print $1}')
      if [[ $got == "$want" ]]; then
        info "OK incoming $file"
      else
        warn "HASH-MISMATCH incoming $file expected=$want got=$got"; bad=1
      fi
    else
      hint="md5 is - in config/incoming.manifest"
      [[ $md5env != - ]] && hint+="; set $md5env to verify"
      warn "NO-HASH incoming $file ($hint)"
    fi
  done <"$tmp"
  rm -f "$tmp"
  return "$bad"
}

# $1: SOURCES dir, $2: group (optional). Verifies md5 before staging.
misl_incoming_stage() {
  local dest=$1 tmp group file md5 md5env kind path want got
  tmp=$(mktemp)
  misl_incoming_wanted "${2:-}" >"$tmp"
  mkdir -p "$dest"
  while IFS=$'\t' read -r group file md5 md5env kind; do
    path=$(misl_incoming_dir)/$file
    [[ -f $path ]] || die "cannot stage missing incoming $file (MISL_GROUPS=$group misl sources fetch)"
    if want=$(misl_incoming_md5 "$file" "$md5" "$md5env"); then
      got=$(md5sum "$path" | awk '{print $1}')
      [[ $got == "$want" ]] || die "HASH-MISMATCH incoming $file expected=$want got=$got"
    fi
    mkdir -p "$(dirname "$dest/$file")"
    if [[ ! -f $dest/$file ]]; then
      ln "$path" "$dest/$file" 2>/dev/null || cp -v "$path" "$dest/$file"
    fi
    if [[ -n ${want:-} ]]; then
      printf '%s  %s\n' "$want" "$(basename "$file")" >"$dest/$file.md5"
    else
      rm -f "$dest/$file.md5"
    fi
    want=
    info "staged incoming ($group) $file"
  done <"$tmp"
  rm -f "$tmp"
}

# `misl groups`: every group, its rows, selected or not.
misl_groups_list() {
  local man stage name ver tarball patches notes g label
  man=$(misl_manifest_file)
  misl_groups_prepare
  printf 'selected: %s%s\n' "$MISL_GROUPS_ALWAYS" "${MISL_GROUPS_SEL% }"
  printf 'targets: %s\n' "$(misl_groups_target_overlays | paste -sd' ' -)"
  for g in $(misl_groups_known); do
    if [[ " $MISL_GROUPS_ALWAYS " == *" $g "* ]]; then label=always
    elif misl_group_selected "$g"; then label=yes; else label=no; fi
    printf '%s (%s) - %s\n ' "$g" "$label" "$(misl_group_meaning "$g")"
    while read -r stage name ver tarball patches notes; do
      [[ -z ${stage:-} || $stage == \#* ]] && continue
      [[ $(misl_groups_of_notes "${notes:-}") == "$g" ]] && printf ' %s' "$name"
    done <"$man"
    misl_incoming_wanted "$g" | while IFS=$'\t' read -r _ file _; do
      printf ' incoming:%s' "$file"
    done
    printf '\n'
  done
}
