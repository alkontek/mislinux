# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.49 OpenSSL-4.0.1
pkg_name=openssl
pkg_version=4.0.1
pkg_tarball=openssl-4.0.1.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" MANSUFFIX=ssl install
  else
    make MANSUFFIX=ssl install
  fi
  [[ -x ${dest}/usr/bin/openssl ]] || die "openssl binary missing after install"
}
