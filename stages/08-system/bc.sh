# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.15 Bc-7.0.3
pkg_name=bc
pkg_version=7.0.3
pkg_tarball=bc-7.0.3.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  # gcc 16 defaults to C23; true/false become keywords and ##UL breaks data.c
  CC="gcc -std=c99" ./configure --prefix=/usr -G -O3 -r
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
}
