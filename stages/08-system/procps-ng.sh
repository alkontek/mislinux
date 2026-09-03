# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.80 Procps-ng-4.0.7
pkg_name=procps-ng
pkg_version=4.0.7
pkg_tarball=procps-ng-4.0.7.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
}
pkg_configure() {
  local sc sl
  # 4.0.7 still asks for libsystemd-login.pc; systemd 261 only has libsystemd.
  if pkg-config --exists libsystemd 2>/dev/null; then
    sc=$(pkg-config --cflags libsystemd)
    sl=$(pkg-config --libs libsystemd)
  else
    sc="-I/usr/include"
    sl="-lsystemd"
  fi
  SYSTEMD_CFLAGS=$sc SYSTEMD_LIBS=$sl \
  ./configure --prefix=/usr \
              --docdir=/usr/share/doc/procps-ng-4.0.7 \
              --disable-static \
              --disable-kill \
              --enable-watch8bit \
              --with-systemd
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
