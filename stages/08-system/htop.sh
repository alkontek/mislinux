# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# htop-3.5.3: ncursesw process viewer.

pkg_name=htop
pkg_version=3.5.3
pkg_tarball=htop-3.5.3.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="ncurses"

pkg_pre_configure() {
  [[ -f /usr/include/ncursesw/ncurses.h || -f /usr/include/ncurses.h \
     || -f ${LFS}/usr/include/ncurses.h ]] || die "htop needs ncurses headers"
}

pkg_configure() {
  # libsensors, libcap and libunwind are optional; autodetected.
  ./configure --prefix=/usr \
              --sysconfdir=/etc \
              --enable-unicode
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
  [[ -x ${dest}/usr/bin/htop ]] || die "htop missing after install"
}
