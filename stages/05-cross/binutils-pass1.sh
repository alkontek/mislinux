# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §5.2 binutils-2.47 pass 1
pkg_name=binutils
pkg_version=2.47
pkg_tarball=binutils-2.47.tar.xz
pkg_patches=
pkg_stage=05-cross
pkg_pass=1
pkg_builddir=build

pkg_configure() {
  ../configure --prefix="$LFS/tools" \
               --with-sysroot="$LFS" \
               --target="$LFS_TGT" \
               --disable-nls \
               --enable-gprofng=no \
               --disable-werror \
               --enable-new-dtags \
               --enable-default-hash-style=gnu
}

pkg_build() {
  # shellcheck disable=SC2086
  make ${MISL_MAKEFLAGS:-}
}

pkg_install() {
  make install
}
