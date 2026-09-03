# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.3 Man-pages-6.18
pkg_name=man-pages
pkg_version=6.18
pkg_tarball=man-pages-6.18.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() { :; }
pkg_build() { :; }

pkg_install() {
  rm -fv man3/crypt*
  local dest prefix
  dest=$(misl_dest)
  prefix=${dest:-}/usr
  make -R GIT=false prefix="$prefix" install
}
