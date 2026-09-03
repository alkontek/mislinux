# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd '8.29 Libxcrypt-4.5.2
pkg_name=libxcrypt
pkg_version=4.5.2
pkg_tarball=libxcrypt-4.5.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  # C23 strchr(const char *) returns const char *; -Werror breaks gcc 16.
  sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
}
pkg_configure() {
  ./configure --prefix=/usr \
              --enable-hashes=strong,glibc \
              --enable-obsolete-api=no \
              --disable-static \
              --disable-failure-tokens
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
