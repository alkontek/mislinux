# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.14 Sed-4.10
pkg_name=sed
pkg_version=4.10
pkg_tarball=sed-4.10.tar.xz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(./build-aux/config.guess)"
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() { make DESTDIR="$LFS" install; }
