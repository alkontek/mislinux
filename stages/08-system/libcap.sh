# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.28 Libcap-2.78
pkg_name=libcap
pkg_version=2.78
pkg_tarball=libcap-2.78.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() { sed -i "/install -m.*STA/d" libcap/Makefile; }
pkg_configure() { :; }
pkg_build() { make prefix=/usr lib=lib ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  make prefix="${dest}/usr" lib=lib install
  rm -fv "${dest}/usr/lib/libcap.a"
}
