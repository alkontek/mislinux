# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# alsa-lib-1.2.16.1: libasound. UCM profiles come from alsa-ucm-conf.

pkg_name=alsa-lib
pkg_version=1.2.16.1
pkg_tarball=alsa-lib-1.2.16.1.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() { ./configure --prefix=/usr --sysconfdir=/etc --disable-static; }

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  make DESTDIR="$dest" install
  [[ -f ${dest}/usr/lib/pkgconfig/alsa.pc ]] || die "alsa.pc missing"
}
