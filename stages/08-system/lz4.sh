# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.9 Lz4-1.10.0
pkg_name=lz4
pkg_version=1.10.0
pkg_tarball=lz4-1.10.0.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() { make PREFIX=/usr ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  make PREFIX="${dest}/usr" install
  rm -fv "${dest}/usr/lib/liblz4.a"
}
