# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.60 Kmod-34.2
pkg_name=kmod
pkg_version=34.2
pkg_tarball=kmod-34.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr --sysconfdir=/etc --with-openssl --with-xz --with-zstd --with-zlib --disable-manpages || \
  meson setup build --prefix=/usr --buildtype=release -D manpages=false
}
pkg_build() {
  if [[ -d build && -f build/build.ninja ]]; then
    ninja -C build
  else
    make ${MISL_MAKEFLAGS:-}
  fi
}
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -d build && -f build/build.ninja ]]; then
    if [[ -n $dest ]]; then DESTDIR="$dest" ninja -C build install; else ninja -C build install; fi
  else
    if [[ -n $dest ]]; then make DESTDIR="$dest" install; else make install; fi
  fi
  for t in depmod insmod lsmod modinfo modprobe rmmod; do
    ln -sfv kmod "${dest}/usr/bin/$t"
  done
}
