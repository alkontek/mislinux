# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.32 GCC-16.2.0 (final)
pkg_name=gcc
pkg_version=16.2.0
pkg_tarball=gcc-16.2.0.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build
pkg_pre_configure() {
  local src
  src=$(cd .. && pwd)
  case $(uname -m) in
    x86_64) sed -e "/m64=/s/lib64/lib/" -i.orig "$src/gcc/config/i386/t-linux64" ;;
  esac
}
pkg_configure() {
  ../configure --prefix=/usr \
               LD=ld \
               --enable-languages=c,c++ \
               --enable-default-pie \
               --enable-default-ssp \
               --enable-host-pie \
               --enable-targets=all \
               --disable-multilib \
               --disable-bootstrap \
               --disable-fixincludes \
               --with-system-zlib
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  ln -sfv gcc "${dest}/usr/bin/cc"
  ln -svr "${dest}/usr/bin/cpp" "${dest}/usr/lib" || ln -sfv ../bin/cpp "${dest}/usr/lib/cpp"
}
