# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.13 Pcre2-10.47
pkg_name=pcre2
pkg_version=10.47
pkg_tarball=pcre2-10.47.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr \
              --docdir=/usr/share/doc/pcre2-10.47 \
              --enable-unicode-properties \
              --enable-pcre2-16 \
              --enable-pcre2-32 \
              --disable-static
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
}
