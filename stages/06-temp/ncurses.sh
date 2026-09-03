# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.3 Ncurses-6.6
pkg_name=ncurses
pkg_version=6.6
pkg_tarball=ncurses-6.6.tar.gz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_pre_configure() {
  mkdir -pv build
  (
    cd build
    ../configure --prefix="$LFS/tools" AWK=gawk
    make -C include
    make -C progs tic
    install progs/tic "$LFS/tools/bin"
  )
}

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(./config.guess)" \
              --mandir=/usr/share/man \
              --with-manpage-format=normal \
              --with-shared \
              --without-normal \
              --with-cxx-shared \
              --without-debug \
              --without-ada \
              --disable-stripping \
              AWK=gawk
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  make DESTDIR="$LFS" install
  ln -sfv libncursesw.so "$LFS/usr/lib/libncurses.so"
  sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
}
