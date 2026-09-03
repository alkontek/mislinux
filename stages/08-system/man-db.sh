# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.79 Man-DB-2.13.1
pkg_name=man-db
pkg_version=2.13.1
pkg_tarball=man-db-2.13.1.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr \
              --docdir=/usr/share/doc/man-db-2.13.1 \
              --sysconfdir=/etc \
              --disable-setuid \
              --enable-cache-owner=bin \
              --with-browser=/usr/bin/lynx \
              --with-vgrind=/usr/bin/vgrind \
              --with-grap=/usr/bin/grap \
              --with-systemdtmpfilesdir= \
              --with-systemdsystemunitdir=
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
