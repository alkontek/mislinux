# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd gmp
pkg_name=gmp
pkg_version=6.3.0
pkg_tarball=gmp-6.3.0.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  [[ -f configfsf.guess ]] && cp -v configfsf.guess config.guess
  [[ -f configfsf.sub ]] && cp -v configfsf.sub config.sub
  # gcc 15+ is C23; the long-long probe uses unprototyped g()/h().
  sed -i '/long long t1;/,+1s/()/(...)/' configure
}
pkg_configure() {
  ABI=64 CC="gcc -std=gnu17" ./configure --prefix=/usr \
    --enable-cxx \
    --disable-static \
    --build=x86_64-pc-linux-gnu \
    --docdir=/usr/share/doc/gmp-6.3.0
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
