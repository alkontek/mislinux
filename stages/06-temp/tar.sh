# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.15 Tar-1.35
pkg_name=tar
pkg_version=1.35
pkg_tarball=tar-1.35.tar.xz
pkg_patches=tar-1.35-acl_fix-1.patch
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(build-aux/config.guess)"
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() { make DESTDIR="$LFS" install; }
