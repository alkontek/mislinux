# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# wget-list + md5sums. Operator fetch is on by default (MISL_FETCH=1).
# Agent sessions must not run `misl sources fetch` (set MISL_FETCH=0).
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

misl_fetch_one() {
  local url=$1 dest=$2
  [[ $(basename "$dest") != wget-list.original ]] || die "refusing wget-list.original"
  if [[ -f $dest ]]; then
    info "have $(basename "$dest")"
    return 0
  fi
  info "FETCH $url"
  wget -c -O "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

misl_sources_fetch() {
  [[ ${MISL_FETCH:-1} == 1 ]] || die "fetch disabled (MISL_FETCH=0); agent sessions must leave fetch off"
  require_cmd wget
  [[ -n ${MISL_MIRROR:-} ]] || die "MISL_MIRROR is not set"
  [[ $(basename "$MISL_WGET_LIST") != wget-list.original ]] || die "refusing wget-list.original"
  misl_snapshot_layout

  # Catalog lives at the snapshot root. wget-list URLs point at
  # $MISL_MIRROR/sources/* and $MISL_MIRROR/patches/*.
  misl_fetch_one "$MISL_MIRROR/wget-list" "$MISL_WGET_LIST"
  misl_fetch_one "$MISL_MIRROR/md5sums" "$MISL_MD5SUMS"

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
