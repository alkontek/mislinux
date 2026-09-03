# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.22 Binutils-2.47 (final)
pkg_name=binutils
pkg_version=2.47
pkg_tarball=binutils-2.47.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build
pkg_configure() {
  ../configure --prefix=/usr \
               --sysconfdir=/etc \
               --enable-ld=default \
               --enable-plugins \
               --enable-shared \
               --disable-werror \
               --enable-64-bit-bfd \
               --enable-new-dtags \
               --enable-default-hash-style=gnu
}
pkg_build() { make tooldir=/usr ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make tooldir=/usr DESTDIR="$dest" install
  else
    make tooldir=/usr install
  fi
  rm -fv "${dest}/usr/lib"/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a
  rm -fv "${dest}/usr/lib"/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.la
}
