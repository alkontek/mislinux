#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# Local-mirror walk through sources integrate. Does not touch the real
# makeitsolinux.org tree or download anything.
set -euo pipefail
MISL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
. "$MISL_ROOT/lib/config.sh"
. "$MISL_ROOT/lib/sources.sh"

work=$(mktemp -d /tmp/misl-integrate-smoke.XXXXXX)
mirror=$work/mirror
snap=$work/snap
lfs=$work/lfs
mkdir -p "$mirror/sources" "$snap" "$lfs"

src=$work/openssh-10.5p1
mkdir -p "$src"
printf 'openssh dummy\n' >"$src/README"
tar -C "$work" -czf "$mirror/sources/openssh-10.5p1.tar.gz" openssh-10.5p1
hash=$(md5sum "$mirror/sources/openssh-10.5p1.tar.gz" | awk '{print $1}')
printf '%s\n' "$mirror/sources/openssh-10.5p1.tar.gz" >"$mirror/wget-list"
printf '%s  sources/openssh-10.5p1.tar.gz\n' "$hash" >"$mirror/md5sums"

mkdir -p "$work/tree/config" "$work/tree/stages/08-system"
printf '%s\n' "08-system openssh 10.5p1 openssh-10.5p1.tar.gz - implemented=0.3 extra=blfs" \
  >"$work/tree/config/packages.manifest"
cat >"$work/tree/stages/08-system/openssh.sh" <<'EOF'
# shellcheck shell=bash
pkg_name=openssh
pkg_version=10.5p1
pkg_tarball=openssh-10.5p1.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() { :; }
pkg_install() { mkdir -p "$LFS/usr/sbin"; printf 'sshd-dummy\n' >"$LFS/usr/sbin/sshd"; }
EOF

export LFS=$lfs
export MISL_FETCH=1
export MISL_MIRROR=$mirror
export MISL_SNAPSHOT=$snap
export MISL_WGET_LIST=$snap/wget-list
export MISL_MD5SUMS=$snap/md5sums
export MISL_SOURCES=$snap/sources
export MISL_PATCHES=$snap/patches
export MISL_MANIFEST=$work/tree/config/packages.manifest
export MISL_ROOT=$work/tree
# Keep real helper libs; recipes live in the temp tree.
export MISL_ROOT
# Restore helper root for lib paths already sourced; only recipes/manifest switch.
# misl_sources_integrate looks at MISL_ROOT for the recipe and manifest override.
# Re-point MISL_ROOT at the temp tree now that libs are loaded.
MISL_ROOT=$work/tree

misl_sources_integrate openssh
[[ -f $snap/sources/openssh-10.5p1.tar.gz ]] || die "tarball not fetched"
[[ -f $lfs/usr/src/misl/SOURCES/openssh-10.5p1.tar.gz ]] || die "tarball not staged"
[[ -f $lfs/var/lib/misl/integrated/openssh ]] || die "missing integrate record"
[[ ! -e $lfs/usr/sbin/sshd ]] || die "integrate must not compile"

# Chroot (LFS=/) must refuse — wget is a host tool.
if ( LFS=/ misl_sources_integrate --reintegrate openssh ) 2>"$work/chroot.err"; then
  die "integrate inside LFS=/ should have been refused"
fi
grep -q "exit the chroot first" "$work/chroot.err" || die "chroot refusal message missing"

if ( misl_sources_integrate openssh ); then
  die "second integrate should have been refused"
fi

# Duplicate final-system name.
printf '%s\n' \
  "08-system openssh 10.5p1 openssh-10.5p1.tar.gz - implemented=0.3 extra=blfs" \
  "08-system openssh 10.6p1 openssh-10.6p1.tar.gz - implemented=0.3 extra=blfs" \
  >"$MISL_MANIFEST"
if ( misl_sources_integrate --reintegrate openssh ) 2>"$work/dup.err"; then
  die "two openssh rows should have been refused"
fi
grep -q "cannot have two openssh" "$work/dup.err" || \
  die "duplicate-name error missing"

# Version bump + --reintegrate replaces the record.
printf '%s\n' "08-system openssh 10.6p1 openssh-10.6p1.tar.gz - implemented=0.3 extra=blfs" \
  >"$MISL_MANIFEST"
src=$work/openssh-10.6p1
mkdir -p "$src"
printf 'openssh dummy 10.6\n' >"$src/README"
tar -C "$work" -czf "$mirror/sources/openssh-10.6p1.tar.gz" openssh-10.6p1
hash=$(md5sum "$mirror/sources/openssh-10.6p1.tar.gz" | awk '{print $1}')
printf '%s\n' \
  "$mirror/sources/openssh-10.5p1.tar.gz" \
  "$mirror/sources/openssh-10.6p1.tar.gz" >"$mirror/wget-list"
printf '%s  sources/openssh-10.5p1.tar.gz\n' \
  "$(md5sum "$mirror/sources/openssh-10.5p1.tar.gz" | awk '{print $1}')" >"$mirror/md5sums"
printf '%s  sources/openssh-10.6p1.tar.gz\n' "$hash" >>"$mirror/md5sums"
cat >"$work/tree/stages/08-system/openssh.sh" <<'EOF'
# shellcheck shell=bash
pkg_name=openssh
pkg_version=10.6p1
pkg_tarball=openssh-10.6p1.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() { :; }
pkg_install() { mkdir -p "$LFS/usr/sbin"; printf 'sshd-dummy-10.6\n' >"$LFS/usr/sbin/sshd"; }
EOF

misl_sources_integrate --reintegrate openssh
grep -q $'openssh\t10.6p1\topenssh-10.6p1.tar.gz' "$lfs/var/lib/misl/integrated/openssh" || \
  die "record was not replaced with 10.6p1"
[[ -f $lfs/usr/src/misl/SOURCES/openssh-10.6p1.tar.gz ]] || die "10.6p1 not staged"
[[ ! -e $lfs/usr/sbin/sshd ]] || die "reintegrate must not compile"
n=$(find "$lfs/var/lib/misl/integrated" -type f | wc -l)
(( n == 1 )) || die "expected one integrated record, got $n"

info "sources-integrate-smoke OK ($work)"
rm -rf "$work"
