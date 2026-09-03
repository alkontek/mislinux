# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.44 Inetutils-2.8
pkg_name=inetutils
pkg_version=2.8
pkg_tarball=inetutils-2.8.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  # ncurses has tgetent in term.h; gcc 16 errors on the implicit decl.
  sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
}
pkg_configure() {
  CC="gcc -std=gnu17" \
  ./configure --prefix=/usr \
              --bindir=/usr/bin \
              --localstatedir=/var \
              --disable-logger \
              --disable-whois \
              --disable-rcp \
              --disable-rexec \
              --disable-rlogin \
              --disable-rsh \
              --disable-servers
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
  mv -v "${dest}/usr/bin/ifconfig" "${dest}/usr/sbin" 2>/dev/null || true
}
