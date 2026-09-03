# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.7 Bzip2-1.0.8
pkg_name=bzip2
pkg_version=1.0.8
pkg_tarball=bzip2-1.0.8.tar.gz
pkg_patches=bzip2-1.0.8-install_docs-1.patch
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree

pkg_pre_configure() {
  sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
  sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
}

pkg_configure() { :; }

pkg_build() {
  make -f Makefile-libbz2_so
  make clean
  make ${MISL_MAKEFLAGS:-}
}

pkg_install() {
  local dest
  dest=$(misl_dest)
  make PREFIX="${dest}/usr" install
  cp -av libbz2.so.* "${dest}/usr/lib"
  ln -sfv libbz2.so.1.0.8 "${dest}/usr/lib/libbz2.so"
  ln -sfv libbz2.so.1.0.8 "${dest}/usr/lib/libbz2.so.1"
  cp -v bzip2-shared "${dest}/usr/bin/bzip2"
  ln -sfv bzip2 "${dest}/usr/bin/bzcat"
  ln -sfv bzip2 "${dest}/usr/bin/bunzip2"
  rm -fv "${dest}/usr/lib/libbz2.a"
}
