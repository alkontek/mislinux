# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.10 Zstd-1.5.7
pkg_name=zstd
pkg_version=1.5.7
pkg_tarball=zstd-1.5.7.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() { make prefix=/usr ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  make prefix="${dest}/usr" install
  rm -fv "${dest}/usr/lib/libzstd.a"
}
