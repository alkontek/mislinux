# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# lsof-4.99.6: built without libtirpc (not in the graph).

pkg_name=lsof
pkg_version=4.99.6
pkg_tarball=lsof-4.99.6.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() {
  # libtirpc is not in the graph; lsof 4.99 treats it as optional
  # (no RPC port-map names without it).
  ./configure --prefix=/usr \
              --disable-static \
              --without-libtirpc
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  [[ -x ${dest}/usr/bin/lsof ]] || die "lsof missing after install"
}
