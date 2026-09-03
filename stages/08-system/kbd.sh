# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.68 Kbd-2.10.0
pkg_name=kbd
pkg_version=2.10.0
pkg_tarball=kbd-2.10.0.tar.xz
pkg_patches=kbd-2.10.0-backspace-1.patch
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() { sed -i "/RESIZECONS_PROGS=/s/yes/no/" configure; sed -i "s/resizecons.8 //" docs/man/man8/Makefile.in; }
pkg_configure() { ./configure --prefix=/usr --disable-vlock; }
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
}
