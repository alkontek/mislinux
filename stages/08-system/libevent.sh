# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# libevent-2.1.13: event loop library (tmux). OpenSSL bufferevents on.
# The tarball top dir is libevent-2.1.13-stable; recipe_main unpacks
# with --strip-components=1, so the name does not matter here.

pkg_name=libevent
pkg_version=2.1.13
pkg_tarball=libevent-2.1.13-stable.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="openssl"

pkg_pre_configure() {
  # event_rpcgen.py: point at python3, no /usr/bin/python in MISL.
  sed -i 's/python\b/&3/' event_rpcgen.py
}

pkg_configure() {
  ./configure --prefix=/usr --disable-static \
    --disable-samples --disable-doxygen-html
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
  [[ -f ${dest}/usr/lib/libevent.so ]] || die "libevent.so missing after install"
}

pkg_check() {
  local dest d
  dest=$(misl_dest)
  for d in libevent libevent_core libevent_openssl; do
    [[ -f ${dest}/usr/lib/pkgconfig/${d}.pc ]] || die "missing ${d}.pc"
  done
  [[ -f ${dest}/usr/include/event2/event.h ]] || die "missing event2/event.h"
  [[ ! -e ${dest}/usr/lib/libevent.a ]] || die "static libevent.a installed"
  misl_check_run pkg-config --exists libevent
}
