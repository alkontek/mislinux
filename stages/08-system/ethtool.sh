# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# ethtool-7.2. Netlink interface needs libmnl, which MISL does not ship
# yet, so --disable-netlink (ioctl only; some newer queries missing).

pkg_name=ethtool
pkg_version=7.2
pkg_tarball=ethtool-7.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() { ./configure --prefix=/usr --sbindir=/usr/sbin --disable-netlink; }

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  make DESTDIR="$dest" install
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -x ${dest}/usr/sbin/ethtool ]] || die "ethtool missing"
  misl_check_run /usr/sbin/ethtool --version
}
