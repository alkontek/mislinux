# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.16 Xz-5.8.3
pkg_name=xz
pkg_version=5.8.3
pkg_tarball=xz-5.8.3.tar.xz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(build-aux/config.guess)" \
              --disable-static \
              --docdir=/usr/share/doc/xz-5.8.3
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  make DESTDIR="$LFS" install
  rm -fv "$LFS/usr/lib/liblzma.la"
}
