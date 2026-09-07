# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Nano-9.2 (BLFS): UTF-8 editor; needs ncurses;

pkg_name=nano
pkg_version=9.2
pkg_tarball=nano-9.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="ncurses"

pkg_pre_configure() {
  [[ -f /usr/include/ncurses.h || -f /usr/include/ncursesw/ncurses.h \
     || -f ${LFS}/usr/include/ncurses.h \
     || -f ${LFS}/usr/include/ncursesw/ncurses.h ]] || \
    die "nano needs ncurses headers"
}

pkg_configure() {
  ./configure --prefix=/usr \
              --sysconfdir=/etc \
              --enable-utf8 \
              --docdir=/usr/share/doc/nano-9.2
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
  install -v -m755 -d "${dest}/usr/share/doc/nano-9.2"
  install -v -m644 doc/sample.nanorc "${dest}/usr/share/doc/nano-9.2" 2>/dev/null || true
  if [[ -f ${dest}/usr/share/doc/nano-9.2/sample.nanorc && ! -e ${dest}/etc/nanorc ]]; then
    install -v -m644 "${dest}/usr/share/doc/nano-9.2/sample.nanorc" "${dest}/etc/nanorc"
  fi
  [[ -x ${dest}/usr/bin/nano ]] || die "nano missing after install"
}
