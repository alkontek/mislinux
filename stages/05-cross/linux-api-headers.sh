# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §5.4 Linux-7.1.8 API headers
pkg_name=linux-api-headers
pkg_version=7.1.8
pkg_tarball=linux-7.1.8.tar.xz
pkg_patches=
pkg_stage=05-cross
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() { :; }

pkg_build() {
  make mrproper
  make headers
  find usr/include -type f ! -name '*.h' -delete
}

pkg_install() {
  cp -rv usr/include "$LFS/usr"
}
