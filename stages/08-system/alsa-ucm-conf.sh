# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# alsa-ucm-conf-1.2.16.1: UCM/UCM2 profiles; data only.

pkg_name=alsa-ucm-conf
pkg_version=1.2.16.1
pkg_tarball=alsa-ucm-conf-1.2.16.1.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="alsa-lib"

pkg_install() {
  local dest
  dest=$(misl_dest)
  install -v -d -m755 "${dest}/usr/share/alsa"
  cp -R --no-preserve=ownership ucm ucm2 "${dest}/usr/share/alsa/"
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -d ${dest}/usr/share/alsa/ucm2 ]] || die "ucm2 missing"
}
