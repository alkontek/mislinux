# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.4 Iana-Etc-20260805
pkg_name=iana-etc
pkg_version=20260805
pkg_tarball=iana-etc-20260805.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() { :; }
pkg_build() { :; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  cp -v services protocols "${dest}/etc"
}
