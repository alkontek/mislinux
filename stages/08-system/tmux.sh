# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# tmux-3.7c: terminal multiplexer (ncurses, libevent).

pkg_name=tmux
pkg_version=3.7c
pkg_tarball=tmux-3.7c.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="ncurses libevent"

pkg_configure() {
  ./configure --prefix=/usr
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
  [[ -x ${dest}/usr/bin/tmux ]] || die "tmux missing after install"
}

pkg_check() {
  misl_check_run /usr/bin/tmux -V
}
