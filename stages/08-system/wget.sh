# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Wget-1.25.0: OpenSSL 4 fix; no libpsl in the graph.

pkg_name=wget
pkg_version=1.25.0
pkg_tarball=wget-1.25.0.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="openssl zlib pcre2"

pkg_configure() {
  local new_line
  new_line='#if !defined OPENSSL_NO_SSL3_METHOD '
  new_line+='&& OPENSSL_VERSION_NUMBER < 0x40000000L'
  sed -i "/SSL3/c $new_line" src/openssl.c
  ./configure --prefix=/usr \
              --sysconfdir=/etc \
              --with-ssl=openssl \
              --without-libpsl
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
  [[ -x ${dest}/usr/bin/wget ]] || die "wget missing after install"
}
