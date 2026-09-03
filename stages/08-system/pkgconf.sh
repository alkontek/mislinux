# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.21 Pkgconf-3.0.5
pkg_name=pkgconf
pkg_version=3.0.5
pkg_tarball=pkgconf-3.0.5.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/pkgconf-3.0.5
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
  ln -sfv pkgconf "${dest}/usr/bin/pkg-config"
  ln -sfv pkgconf.1 "${dest}/usr/share/man/man1/pkg-config.1"
}
