# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash

# wget-list + md5sums.
# No process substitution — this workspace has no /dev/fd.

misl_is_unused() {
  local name=$1 f=$MISL_ROOT/config/unused-sysv.list line
  [[ -f $f ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line//[$'\t\r ']/}
    [[ $line == "$name" ]] && return 0
  done < "$f"
  return 1
}

misl_assert_wget_list() {
  [[ $(basename "${MISL_WGET_LIST:?}") != wget-list.original ]] || die "refusing wget-list.original"
  [[ -f $MISL_WGET_LIST ]] || \
    die "missing wget-list: $MISL_WGET_LIST (run: misl sources fetch)"
}

misl_md5_for() {
  local name=$1
  # md5sums is `hash  sources/foo.tar.xz` (or patches/…). Match basename or full path.
  awk -v n="$name" '
    {
      p=$2
      sub(/^\*\*/, "", p)
      base=p
      sub(/^.*\//, "", base)
      if (p==n || base==n) { print $1; found=1; exit }
    }
    END { exit found?0:1 }
  ' "${MISL_MD5SUMS:?}"
}

misl_locate() {
  local name=$1
  if [[ $name == *.patch ]]; then
    [[ -f $MISL_PATCHES/$name ]] && { printf '%s\n' "$MISL_PATCHES/$name"; return 0; }
    [[ -f $MISL_SOURCES/$name ]] && { printf '%s\n' "$MISL_SOURCES/$name"; return 0; }
  else
    [[ -f $MISL_SOURCES/$name ]] && { printf '%s\n' "$MISL_SOURCES/$name"; return 0; }
    [[ -f $MISL_PATCHES/$name ]] && { printf '%s\n' "$MISL_PATCHES/$name"; return 0; }
  fi
  return 1
}

misl_each_wget() {
  # prints: url<TAB>name
  local url name
  misl_assert_wget_list
  while IFS= read -r url || [[ -n $url ]]; do
    url=${url%%#*}
    url=${url//[$'\t\r ']/}
    [[ -n $url ]] || continue
    name=${url##*/}
    printf '%s\t%s\n' "$url" "$name"
  done < "$MISL_WGET_LIST"
}

misl_sources_check() {
  local url name path expect actual missing=0 mismatch=0 unused_ok=0 needed=0 tmp
  info "checking sources against $MISL_WGET_LIST"
  info "md5sums=$MISL_MD5SUMS sources=$MISL_SOURCES patches=$MISL_PATCHES"
  tmp=$(mktemp)
  misl_each_wget >"$tmp"
  while IFS=$'\t' read -r url name; do
    needed=$((needed + 1))
    if misl_is_unused "$name"; then
      info "UNUSED-SYSV $name"
      unused_ok=$((unused_ok + 1))
      continue
    fi
    if ! path=$(misl_locate "$name"); then
      warn "MISSING $name"
      missing=$((missing + 1))
      continue
    fi
    if ! expect=$(misl_md5_for "$name"); then
      warn "MISSING-HASH $name"
      missing=$((missing + 1))
      continue
    fi
    actual=$(md5sum "$path" | awk '{print $1}')
    if [[ $actual != "$expect" ]]; then
      warn "HASH-MISMATCH $name expected=$expect got=$actual"
      mismatch=$((mismatch + 1))
    else
      info "OK $name"
    fi
  done < "$tmp"
  rm -f "$tmp"

  info "needed=$needed missing=$missing mismatch=$mismatch unused-skipped=$unused_ok"
  if (( missing + mismatch > 0 )); then
    return 1
  fi
  return 0
}

misl_sources_stage() {
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory (mount it first)"
  local dest=$LFS/usr/src/misl tmp url name path
  mkdir -pv "$dest"/{SOURCES,SPECS,SRPMS,RPMS/x86_64,RPMS/noarch} \
            "$LFS/var/lib/misl"/{stamps,logs,pkglog}
  tmp=$(mktemp)
  misl_each_wget >"$tmp"
  while IFS=$'\t' read -r url name; do
    misl_is_unused "$name" && continue
    path=$(misl_locate "$name") || die "cannot stage missing $name"
    if [[ -f $dest/SOURCES/$name ]]; then
      info "already staged $name"
    elif ln "$path" "$dest/SOURCES/$name" 2>/dev/null; then
      info "hardlink $name"
    else
      cp -v "$path" "$dest/SOURCES/$name"
    fi
  done < "$tmp"
  rm -f "$tmp"
}

# Host-wide snapshot at /var/cache/misl/... is writable by root and lfs.
misl_snapshot_share() {
  local cache parent
  [[ -n ${MISL_SNAPSHOT:-} ]] || return 0
  cache=$MISL_SNAPSHOT
  parent=$(dirname "$cache")
  mkdir -pv "$cache"
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    mkdir -pv "$parent"
    chmod 0755 "$parent" "$cache" || true
    if getent passwd lfs >/dev/null 2>&1; then
      chown -R lfs:lfs "$parent"
    fi
  fi
}

# Create $MISL_SNAPSHOT and pull catalog + wget-list from MISL_MIRROR.
# Never wget-list.original.
misl_snapshot_layout() {
  [[ -n ${MISL_SNAPSHOT:-} ]] || die "MISL_SNAPSHOT is not set"
  misl_snapshot_share
  mkdir -pv "$MISL_SNAPSHOT" "$MISL_SOURCES" "$MISL_PATCHES"
  misl_snapshot_share
}

misl_manifest_file() {
  printf '%s\n' "${MISL_MANIFEST:-$MISL_ROOT/config/packages.manifest}"
}

misl_integrated_dir() {
  require_lfs_set
  printf '%s/var/lib/misl/integrated\n' "${LFS%/}"
}

misl_integrated_record() {
  local name=$1
  printf '%s/%s\n' "$(misl_integrated_dir)" "$name"
}

# One final-system name (08/09/10). Toolchain 05–07 may repeat names.
misl_manifest_assert_single_final() {
  local want=$1 man line stage name ver tarball rest n=0 tmp
  man=$(misl_manifest_file)
  [[ -f $man ]] || die "missing packages.manifest: $man"
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == \#* || -z $line ]] && continue
    stage=${line%% *}
    case $stage in
      08-system|09-config|10-boot) ;;
      *) continue ;;
    esac
    name=$(awk '{print $2}' <<<"$line")
    [[ $name == "$want" ]] || continue
    n=$((n + 1))
    printf '%s\n' "$line" >>"$tmp"
  done < "$man"
  if (( n > 1 )); then
    warn "duplicate final-system rows for $want:"
    cat "$tmp" >&2
    rm -f "$tmp"
    die "cannot have two $want packages; edit packages.manifest or --reintegrate the one row"
  fi
  rm -f "$tmp"
}

# Resolve name or tarball or stage/name -> prints: stage name version tarball patches
misl_manifest_pick() {
  local arg=$1 want_stage= man line stage name ver tarball patches rest
  local tmp hits first
  [[ -n $arg ]] || return 1
  if [[ $arg == */* ]]; then
    want_stage=${arg%%/*}
    arg=${arg##*/}
  fi
  man=$(misl_manifest_file)
  [[ -f $man ]] || die "missing packages.manifest: $man"
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == \#* || -z $line ]] && continue
    stage=$(awk '{print $1}' <<<"$line")
    name=$(awk '{print $2}' <<<"$line")
    ver=$(awk '{print $3}' <<<"$line")
    tarball=$(awk '{print $4}' <<<"$line")
    patches=$(awk '{print $5}' <<<"$line")
    [[ -n $stage && -n $name ]] || continue
    [[ -z $want_stage || $stage == "$want_stage" ]] || continue
    if [[ $name == "$arg" || $tarball == "$arg" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$stage" "$name" "$ver" "$tarball" "$patches"
    fi
  done < "$man" >"$tmp"
  hits=$(grep -c . "$tmp" || true)
  if (( hits == 0 )); then
    rm -f "$tmp"
    return 1
  fi
  if (( hits == 1 )); then
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi
  # Prefer the chapter-8 system row when the same name is in the toolchain.
  first=$(awk -F'\t' '$1=="08-system" {print; exit}' "$tmp")
  if [[ -n $first ]]; then
    printf '%s\n' "$first"
    rm -f "$tmp"
    return 0
  fi
  warn "ambiguous package $arg:"
  cat "$tmp" >&2
  rm -f "$tmp"
  die "use stage/name (example: 08-system/$arg)"
}

misl_url_for() {
  local name=$1 url file
  misl_assert_wget_list
  while IFS= read -r url || [[ -n $url ]]; do
    url=${url%%#*}
    url=${url//[$'\t\r ']/}
    [[ -n $url ]] || continue
    file=${url##*/}
    if [[ $file == "$name" ]]; then
      printf '%s\n' "$url"
      return 0
    fi
  done < "$MISL_WGET_LIST"
  return 1
}

misl_dest_for_name() {
  local name=$1
  if [[ $name == *.patch ]]; then
    printf '%s/%s\n' "${MISL_PATCHES:?}" "$name"
  else
    printf '%s/%s\n' "${MISL_SOURCES:?}" "$name"
  fi
}

# Third arg force=1 replaces an existing file (catalog refresh, --reintegrate).
misl_fetch_one() {
  local url=$1 dest=$2 force=${3:-0}
  [[ $(basename "$dest") != wget-list.original ]] || die "refusing wget-list.original"
  if [[ -f $dest && $force != 1 ]]; then
    info "have $(basename "$dest")"
    return 0
  fi
  mkdir -pv "$(dirname "$dest")"
  info "FETCH $url"
  if [[ $url == /* ]]; then
    [[ -f $url ]] || die "local source missing: $url"
    cp -f "$url" "$dest.part"
  elif [[ $url == file://* ]]; then
    url=${url#file://}
    [[ -f $url ]] || die "local source missing: $url"
    cp -f "$url" "$dest.part"
  else
    require_cmd wget
    wget -c -O "$dest.part" "$url"
  fi
  mv "$dest.part" "$dest"
}

misl_sources_fetch() {
  [[ ${MISL_FETCH:-1} == 1 ]] || die "fetch disabled (MISL_FETCH=0); agent sessions must leave fetch off"
  require_cmd wget
  [[ -n ${MISL_MIRROR:-} ]] || die "MISL_MIRROR is not set"
  [[ $(basename "$MISL_WGET_LIST") != wget-list.original ]] || die "refusing wget-list.original"
  misl_snapshot_layout

  # Catalog lives at the snapshot root. Always refresh it so a package
  # added to the remote wget-list mid-build is visible on the next fetch.
  # wget-list URLs point at $MISL_MIRROR/sources/* and $MISL_MIRROR/patches/*.
  misl_catalog_refresh_files

  local tmp url name dest
  tmp=$(mktemp)
  misl_each_wget >"$tmp"
  while IFS=$'\t' read -r url name; do
    [[ $name != wget-list.original ]] || continue
    misl_is_unused "$name" && { info "SKIP unused-sysv $name"; continue; }
    if [[ $name == *.patch ]]; then
      dest=$MISL_PATCHES/$name
    else
      dest=$MISL_SOURCES/$name
    fi
    misl_fetch_one "$url" "$dest"
  done < "$tmp"
  rm -f "$tmp"
  info "snapshot=$MISL_SNAPSHOT"
}

misl_catalog_refresh_files() {
  [[ -n ${MISL_MIRROR:-} ]] || die "MISL_MIRROR is not set"
  [[ $(basename "${MISL_WGET_LIST:?}") != wget-list.original ]] || die "refusing wget-list.original"
  misl_snapshot_layout
  misl_fetch_one "$MISL_MIRROR/wget-list" "$MISL_WGET_LIST" 1
  misl_fetch_one "$MISL_MIRROR/md5sums" "$MISL_MD5SUMS" 1
  info "catalog wget-list=$MISL_WGET_LIST md5sums=$MISL_MD5SUMS"
}

misl_catalog_refresh() {
  [[ ${MISL_FETCH:-1} == 1 ]] || die "fetch disabled (MISL_FETCH=0); agent sessions must leave fetch off"
  misl_catalog_refresh_files
}

# Probe the mirror catalog. No download, allowed when MISL_FETCH=0.
misl_sources_remote() {
  local url fail=0
  [[ -n ${MISL_MIRROR:-} ]] || die "MISL_MIRROR is not set"
  require_cmd wget
  info "HEAD $MISL_MIRROR (no download)"
  for url in "$MISL_MIRROR/wget-list" "$MISL_MIRROR/md5sums"; do
    if wget -q --spider --timeout=20 --tries=2 "$url"; then
      info "OK $url"
    else
      warn "FAIL $url"
      fail=1
    fi
  done
  (( fail == 0 )) || die "mirror HEAD failed"
}

misl_stage_file() {
  local name=$1 dest path root
  require_lfs_set
  root=${LFS%/}
  dest=$root/usr/src/misl/SOURCES
  mkdir -pv "$dest" \
            "$root/usr/src/misl/SPECS" \
            "$root/usr/src/misl/SRPMS" \
            "$root/usr/src/misl/RPMS/x86_64" \
            "$root/usr/src/misl/RPMS/noarch" \
            "$root/var/lib/misl/stamps" \
            "$root/var/lib/misl/logs" \
            "$root/var/lib/misl/pkglog" \
            "$(misl_integrated_dir)"
  path=$(misl_locate "$name") || die "cannot stage missing $name"
  if [[ -f $dest/$name ]]; then
    if cmp -s "$path" "$dest/$name"; then
      info "already staged $name"
      return 0
    fi
    info "replace staged $name"
    rm -f "$dest/$name"
  fi
  if ln "$path" "$dest/$name" 2>/dev/null; then
    info "hardlink $name"
  else
    cp -v "$path" "$dest/$name"
  fi
}

misl_fetch_named_files() {
  local force=${1:-0} name url dest expect actual
  shift
  for name in "$@"; do
    [[ -n $name && $name != - ]] || continue
    url=$(misl_url_for "$name") || die "$name not in wget-list (refresh catalog / upload the tarball)"
    dest=$(misl_dest_for_name "$name")
    misl_fetch_one "$url" "$dest" "$force"
    if expect=$(misl_md5_for "$name" 2>/dev/null); then
      actual=$(md5sum "$dest" | awk '{print $1}')
      [[ $actual == "$expect" ]] || die "HASH-MISMATCH $name expected=$expect got=$actual"
      info "OK $name md5=$actual"
    else
      warn "MISSING-HASH $name (mirror md5sums not filled yet)"
    fi
    misl_stage_file "$name"
  done
}

misl_assert_host_integrate() {
  local root=${LFS:-}
  # Only LFS=/ means the chroot. Do not call misl_in_chroot here: some
  # hosts have / != /proc/1/root and would be blocked forever.
  if [[ $root == / ]]; then
    die "integrate runs on the host (needs wget). exit the chroot first"
  fi
  if [[ -z $root ]]; then
    die "LFS is not set; mount the target and set LFS in config/misl.conf"
  fi
}

misl_integrate_next_steps() {
  local stage=$1 name=$2 ver=$3 re=$4 stamp=$5 force=
  [[ $re == 1 || -f $stamp ]] && force='MISL_FORCE=1 '
  cat <<EOF

$name $ver is on the snapshot and staged at \$LFS/usr/src/misl/SOURCES.
wget is a host tool. Build inside the chroot:

  ./misl enter
  ${force}./misl build $stage/$name

Or from a shell already in the chroot (cwd /usr/src/misl/mislinux):

  ${force}./misl build $stage/$name
EOF
}

# Mid-build, host only: refresh catalog, pull one package, stage onto $LFS.
# Does not compile (no wget in the chroot). Prints enter + build next.
# One registry row per package name. --reintegrate replaces that row.
misl_sources_integrate() {
  local re=0 arg line stage name ver tarball patches rec stamp files
  while [[ $# -gt 0 ]]; do
    case $1 in
      --reintegrate|-R|--force) re=1; shift ;;
      -h|--help)
        printf '%s\n' "usage: misl sources integrate [--reintegrate] <name|stage/name|tarball>"
        return 0
        ;;
      --) shift; break ;;
      -*) die "unknown option $1 (want: --reintegrate)" ;;
      *) break ;;
    esac
  done
  arg=${1:-}
  [[ -n $arg ]] || die "usage: misl sources integrate [--reintegrate] <name|stage/name|tarball>"
  [[ $# -eq 1 ]] || die "integrate one package at a time (got: $*)"

  [[ ${MISL_FETCH:-1} == 1 ]] || die "fetch disabled (MISL_FETCH=0); agent sessions must leave fetch off"
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory (mount it first)"
  misl_assert_host_integrate

  misl_catalog_refresh_files

  line=$(misl_manifest_pick "$arg") || \
    die "$arg is not in packages.manifest (add the row and stages/*/$(basename "$arg").sh first)"
  stage=$(awk -F'\t' '{print $1}' <<<"$line")
  name=$(awk -F'\t' '{print $2}' <<<"$line")
  ver=$(awk -F'\t' '{print $3}' <<<"$line")
  tarball=$(awk -F'\t' '{print $4}' <<<"$line")
  patches=$(awk -F'\t' '{print $5}' <<<"$line")

  [[ -f $MISL_ROOT/stages/$stage/${name}.sh ]] || \
    die "no recipe stages/$stage/${name}.sh"

  misl_manifest_assert_single_final "$name"

  rec=$(misl_integrated_record "$name")
  stamp=${LFS%/}/var/lib/misl/stamps/${stage}-${name}-1.done
  if [[ $re != 1 ]]; then
    if [[ -f $rec ]]; then
      die "already integrated $name ($(tr '\t' ' ' <"$rec")); use: misl sources integrate --reintegrate $name"
    fi
    if [[ -f $stamp ]]; then
      die "already built $stage/$name (stamp exists); use: misl sources integrate --reintegrate $name"
    fi
  fi

  files=$tarball
  if [[ -n $patches && $patches != - ]]; then
    patches=${patches//,/ }
    files="$files $patches"
  fi
  # shellcheck disable=SC2086
  misl_fetch_named_files "$re" $files

  mkdir -pv "$(misl_integrated_dir)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$ver" "$tarball" "$stage" "$re" "$(date -u +%FT%TZ)" >"$rec"
  info "integrated $name $ver ($tarball) record=$rec"
  misl_integrate_next_steps "$stage" "$name" "$ver" "$re" "$stamp"
}
