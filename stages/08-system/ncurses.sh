# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.33 Ncurses-6.6
pkg_name=ncurses
pkg_version=6.6
pkg_tarball=ncurses-6.6.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr \
              --mandir=/usr/share/man \
              --with-shared \
              --without-debug \
              --without-normal \
              --with-cxx-shared \
              --enable-pc-files \
              --with-pkg-config-libdir=/usr/lib/pkgconfig \
              --enable-widec \
              --disable-stripping
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  for lib in ncurses form panel menu; do
    ln -sfv lib${lib}w.so "${dest}/usr/lib/lib${lib}.so"
    ln -sfv ${lib}w.pc "${dest}/usr/lib/pkgconfig/${lib}.pc"
  done
  ln -sfv libncursesw.so "${dest}/usr/lib/libcurses.so"
}
