# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.82 E2fsprogs-1.47.4
pkg_name=e2fsprogs
pkg_version=1.47.4
pkg_tarball=e2fsprogs-1.47.4.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build

pkg_configure() {
  ../configure --prefix=/usr \
               --sysconfdir=/etc \
               --enable-elf-shlibs \
               --disable-libblkid \
               --disable-libuuid \
               --disable-uuidd \
               --disable-fsck
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
  rm -fv "${dest}/usr/lib"/{libcom_err,libe2p,libext2fs,libss}.a
}
