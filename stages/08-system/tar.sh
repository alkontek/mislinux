# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.72 Tar-1.35
pkg_name=tar
pkg_version=1.35
pkg_tarball=tar-1.35.tar.xz
pkg_patches=tar-1.35-acl_fix-1.patch
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr; }
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
