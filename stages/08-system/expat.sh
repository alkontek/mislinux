# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.43 Expat-2.8.3
pkg_name=expat
pkg_version=2.8.3
pkg_tarball=expat-2.8.3.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/expat-2.8.3; }
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
