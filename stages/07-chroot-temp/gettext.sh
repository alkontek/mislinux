# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §7.7 Gettext-1.0
pkg_name=gettext
pkg_version=1.0
pkg_tarball=gettext-1.0.tar.xz
pkg_patches=
pkg_stage=07-chroot-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --disable-shared
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} "${dest}/usr/bin"
}
