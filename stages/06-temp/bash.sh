# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.4 Bash-5.3
pkg_name=bash
pkg_version=5.3
pkg_tarball=bash-5.3.tar.gz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --build="$(sh support/config.guess)" \
              --host="$LFS_TGT" \
              --without-bash-malloc \
              --docdir=/usr/share/doc/bash-5.3
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  make DESTDIR="$LFS" install
  ln -sfv bash "$LFS/bin/sh"
}
