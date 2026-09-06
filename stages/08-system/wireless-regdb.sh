# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# wireless-regdb-2026.09.03: signed regulatory.db for cfg80211.
# Prebuilt in the tarball; nothing to compile.

pkg_name=wireless-regdb
pkg_version=2026.09.03
pkg_tarball=wireless-regdb-2026.09.03.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_install() {
  local dest
  dest=$(misl_dest)
  install -v -d -m755 "${dest}/usr/lib/firmware" "${dest}/usr/share/man/man5"
  install -v -m644 regulatory.db regulatory.db.p7s "${dest}/usr/lib/firmware/"
  install -v -m644 regulatory.db.5 "${dest}/usr/share/man/man5/"
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -s ${dest}/usr/lib/firmware/regulatory.db ]] || die "regulatory.db missing"
  [[ -s ${dest}/usr/lib/firmware/regulatory.db.p7s ]] || die "regulatory.db.p7s missing"
}
