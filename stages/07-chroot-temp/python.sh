# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §7 Python-3.14.7 (openssl patch is chapter 8)
pkg_name=python
pkg_version=3.14.7
pkg_tarball=Python-3.14.7.tar.xz
pkg_patches=
pkg_stage=07-chroot-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --enable-shared \
              --without-ensurepip
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
