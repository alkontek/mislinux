# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.7 File-5.48
pkg_name=file
pkg_version=5.48
pkg_tarball=file-5.48.tar.gz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_pre_configure() {
  mkdir -pv build
  (
    cd build
    ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib
    make
  )
}

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(./config.guess)"
}

pkg_build() {
  make ${MISL_MAKEFLAGS:-} FILE_COMPILE="$(pwd)/build/src/file"
}

pkg_install() {
  make DESTDIR="$LFS" install
  rm -fv "$LFS/usr/lib/libmagic.la"
}
