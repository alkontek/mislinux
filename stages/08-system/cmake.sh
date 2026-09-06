# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# CMake-4.4.3: bundled curl/libarchive/libuv/nghttp2 (not in the graph).

pkg_name=cmake
pkg_version=4.4.3
pkg_tarball=cmake-4.4.3.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="zlib ncurses openssl"

pkg_configure() {
  sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake
  # libuv, libarchive, nghttp2, curl are not
  # built before cmake here, so every third-party lib is bundled.
  ./bootstrap --prefix=/usr \
              --no-system-libs \
              --mandir=/share/man \
              --parallel="$(nproc)" \
              --docdir=/share/doc/cmake-4.4.3
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
  [[ -x ${dest}/usr/bin/cmake ]] || die "cmake missing after install"
}
