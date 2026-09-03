# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.18 Expect-5.45.4
pkg_name=expect
pkg_version=5.45.4
pkg_tarball=expect5.45.4.tar.gz
pkg_patches=expect-5.45.4-gcc15-1.patch
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr \
              --with-tcl=/usr/lib \
              --enable-shared \
              --disable-rpath \
              --mandir=/usr/share/man \
              --with-tclinclude=/usr/include
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  ln -sfv expect5.45.4/libexpect5.45.4.so "${dest}/usr/lib"
}
