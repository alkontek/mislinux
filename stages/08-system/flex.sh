# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.16 Flex-2.6.4
pkg_name=flex
pkg_version=2.6.4
pkg_tarball=flex-2.6.4.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.6.4 --disable-static
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
  ln -sfv flex "${dest}/usr/bin/lex"
  ln -sfv flex.1 "${dest}/usr/share/man/man1/lex.1"
}
