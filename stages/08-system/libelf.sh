# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.50 Libelf from Elfutils-0.195
pkg_name=libelf
pkg_version=0.195
pkg_tarball=elfutils-0.195.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  command -v pkg-config >/dev/null 2>&1 || \
    die "libelf needs pkg-config (./misl build pkgconf)"
}
pkg_configure() {
  ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make -C libelf DESTDIR="$dest" install
    install -vm644 config/libelf.pc "${dest}/usr/lib/pkgconfig"
  else
    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm -fv /usr/lib/libelf.a
  fi
  rm -fv "${dest}/usr/lib/libelf.a"
  [[ -f ${dest}/usr/include/gelf.h || -f /usr/include/gelf.h ]] || \
    die "libelf did not install gelf.h"
}
