# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# iw-6.17: nl80211 CLI (libnl-3 genl).

pkg_name=iw
pkg_version=6.17
pkg_tarball=iw-6.17.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="libnl pkgconf"

pkg_build() { make ${MISL_MAKEFLAGS:-} PREFIX=/usr SBINDIR=/usr/sbin; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  make DESTDIR="$dest" PREFIX=/usr SBINDIR=/usr/sbin install
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -x ${dest}/usr/sbin/iw ]] || die "iw missing"
  misl_check_run /usr/sbin/iw --version
}
