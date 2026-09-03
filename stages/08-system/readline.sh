# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.12 Readline-8.3
pkg_name=readline
pkg_version=8.3
pkg_tarball=readline-8.3.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  sed -i "/MV.*old/d" Makefile.in
  sed -i "/{OLDSUFF}/c:" support/shlib-install
  sed -i "s/-Wl,-rpath,[^ ]* //" support/shobj-conf
}
pkg_configure() {
  ./configure --prefix=/usr --disable-static --with-curses
}
pkg_build() { make SHLIB_LIBS="-lncursesw" ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make SHLIB_LIBS="-lncursesw" DESTDIR="$dest" install
  else
    make SHLIB_LIBS="-lncursesw" install
  fi
}
