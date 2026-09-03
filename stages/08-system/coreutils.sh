# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.61 Coreutils-9.11
pkg_name=coreutils
pkg_version=9.11
pkg_tarball=coreutils-9.11.tar.xz
pkg_patches=coreutils-9.11-i18n-1.patch
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  autoreconf -fv 2>/dev/null || true
  FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --enable-no-install-program=kill,uptime
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then make DESTDIR="$dest" install; else make install; fi
  mv -v "${dest}/usr/bin/chroot" "${dest}/usr/sbin"
  mkdir -pv "${dest}/usr/share/man/man8"
  mv -v "${dest}/usr/share/man/man1/chroot.1" "${dest}/usr/share/man/man8/chroot.8"
  sed -i "s/\"1\"/\"8\"/" "${dest}/usr/share/man/man8/chroot.8"
}
