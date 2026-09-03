# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.39 Bash-5.3
pkg_name=bash
pkg_version=5.3
pkg_tarball=bash-5.3.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr \
              --without-bash-malloc \
              --with-installed-readline \
              --docdir=/usr/share/doc/bash-5.3
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
  ln -sfv bash "${dest}/bin/sh" 2>/dev/null || ln -sfv bash "${dest}/usr/bin/sh"
}
