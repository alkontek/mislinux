# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# libnl-3.12.0: netlink libraries for wpa_supplicant.

pkg_name=libnl
pkg_version=3.12.0
pkg_tarball=libnl-3.12.0.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() {
  ./configure --prefix=/usr \
              --sysconfdir=/etc \
              --disable-static
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  [[ -f ${dest}/usr/include/libnl3/netlink/netlink.h ]] || die "libnl headers missing after install"
}
