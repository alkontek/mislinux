# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §5.6 Libstdc++ from GCC-16.2.0
# Filename avoids '++' which this workspace cannot store.
pkg_name=libstdc++
pkg_version=16.2.0
pkg_tarball=gcc-16.2.0.tar.xz
pkg_patches=
pkg_stage=05-cross
pkg_pass=1
pkg_builddir=build

pkg_configure() {
  ../libstdc++-v3/configure --host="$LFS_TGT" \
                            --build="$(../config.guess)" \
                            CXX="$LFS_TGT-gcc" \
                            --prefix=/usr \
                            --disable-multilib \
                            --disable-nls \
                            --disable-libstdcxx-pch \
                            --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/$pkg_version
}

pkg_build() {
  # shellcheck disable=SC2086
  make ${MISL_MAKEFLAGS:-}
}

pkg_install() {
  make DESTDIR="$LFS" install
  rm -fv "$LFS/usr/lib"/lib{stdc++{,exp,fs},supc++}.la
}
