# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.17 Binutils-2.47 pass 2
pkg_name=binutils
pkg_version=2.47
pkg_tarball=binutils-2.47.tar.xz
pkg_patches=
pkg_stage=06-temp
pkg_pass=2
pkg_builddir=build

pkg_pre_configure() {
  sed '6031s/$add_dir//' -i ../ltmain.sh
}

pkg_configure() {
  ../configure --prefix=/usr \
               --build="$(../config.guess)" \
               --host="$LFS_TGT" \
               --disable-nls \
               --enable-shared \
               --enable-gprofng=no \
               --disable-werror \
               --enable-64-bit-bfd \
               --enable-new-dtags \
               --enable-default-hash-style=gnu
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  misl_make_install DESTDIR="$LFS" install
  rm -fv "$LFS/usr/lib"/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.la
}
