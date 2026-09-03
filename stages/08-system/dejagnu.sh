# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.19 DejaGNU-1.6.3
pkg_name=dejagnu
pkg_version=1.6.3
pkg_tarball=dejagnu-1.6.3.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build
pkg_configure() { ../configure --prefix=/usr; }
pkg_build() { makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi || true
  makeinfo --plaintext -o doc/dejagnu.txt ../doc/dejagnu.texi || true
}
pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  install -v -dm755 "${dest}/usr/share/doc/dejagnu-1.6.3"
  install -v -m644 doc/dejagnu.{html,txt} "${dest}/usr/share/doc/dejagnu-1.6.3" 2>/dev/null || true
}
