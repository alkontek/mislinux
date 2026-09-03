# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.74 Vim-9.2.1025
pkg_name=vim
pkg_version=9.2.1025
pkg_tarball=vim-9.2.1025.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() { echo "#define SYS_VIMRC_FILE \"/etc/vimrc\"" >> src/feature.h; }
pkg_configure() {
  ./configure --prefix=/usr --with-features=huge --enable-multibyte --with-tlib=ncursesw
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then make DESTDIR="$dest" install; else make install; fi
  ln -sfv vim "${dest}/usr/bin/vi"
  printf "%s\n" "set nocompatible" "set backspace=2" "set mouse=" "syntax on" \
    > "${dest}/etc/vimrc"
}
