# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.17 Tcl-8.6.18
pkg_name=tcl
pkg_version=8.6.18
pkg_tarball=tcl8.6.18-src.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  # Hooks share one cwd. Stay in unix/ after this.
  SRCDIR=$(pwd)
  export SRCDIR
  cd "$SRCDIR/unix"
  ./configure --prefix=/usr --mandir=/usr/share/man --disable-rpath
}
pkg_build() {
  make ${MISL_MAKEFLAGS:-}
}
pkg_install() {
  local dest; dest=$(misl_dest)
  sed -e "s|$SRCDIR/unix|/usr/lib|" -e "s|$SRCDIR|/usr/include|" -i tclConfig.sh
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
    make DESTDIR="$dest" install-private-headers
  else
    make install
    make install-private-headers
  fi
  ln -sfv tclsh8.6 "${dest}/usr/bin/tclsh"
  chmod -v u+w "${dest}/usr/lib/libtcl8.6.so"
}
