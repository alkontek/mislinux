# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.6 Diffutils-3.12
pkg_name=diffutils
pkg_version=3.12
pkg_tarball=diffutils-3.12.tar.xz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(./build-aux/config.guess)" \
              gl_cv_func_strcasecmp_works=yes
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() { make DESTDIR="$LFS" install; }
