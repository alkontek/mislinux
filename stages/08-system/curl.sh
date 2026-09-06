# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# cURL-8.22.0: OpenSSL; no libpsl/nghttp2 in the graph.

pkg_name=curl
pkg_version=8.22.0
pkg_tarball=curl-8.22.0.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="openssl zlib zstd"

pkg_pre_configure() {
  [[ -f /usr/include/openssl/ssl.h || -f ${LFS}/usr/include/openssl/ssl.h ]] || \
    die "curl needs openssl headers"
}

pkg_configure() {
  # libpsl is recommended upstream but not on the mirror. No CA store
  # (make-ca) yet: --with-ca-path points where it will live.
  ./configure --prefix=/usr \
              --disable-static \
              --with-openssl \
              --without-libpsl \
              --with-ca-path=/etc/ssl/certs
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
  rm -rf docs/examples/.deps
  find docs \( -name Makefile\* -o -name \*.1 -o -name \*.3 -o -name CMakeLists.txt \) -delete
  cp -v -R docs -T "${dest}/usr/share/doc/curl-8.22.0"
  [[ -x ${dest}/usr/bin/curl ]] || die "curl missing after install"
}
