# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.5 Coreutils-9.11 (no i18n patch in ch6)
pkg_name=coreutils
pkg_version=9.11
pkg_tarball=coreutils-9.11.tar.xz
pkg_patches=
pkg_stage=06-temp
pkg_pass=1
pkg_builddir=in-tree

pkg_configure() {
  ./configure --prefix=/usr \
              --host="$LFS_TGT" \
              --build="$(build-aux/config.guess)" \
              --enable-install-program=hostname
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  make DESTDIR="$LFS" install
  mv -v "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
  mkdir -pv "$LFS/usr/share/man/man8"
  mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
  sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"
}
