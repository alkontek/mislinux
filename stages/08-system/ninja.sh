# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.20 Ninja-1.13.2
pkg_name=ninja
pkg_version=1.13.2
pkg_tarball=ninja-1.13.2.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() { python3 configure.py --bootstrap; }
pkg_install() {
  local dest; dest=$(misl_dest)
  install -vm755 ninja "${dest}/usr/bin/"
  install -vDm644 misc/bash-completion "${dest}/usr/share/bash-completion/completions/ninja"
  install -vDm644 misc/zsh-completion "${dest}/usr/share/zsh/site-functions/_ninja"
}
