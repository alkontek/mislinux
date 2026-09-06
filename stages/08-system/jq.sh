# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# jq-1.8.2: bundled oniguruma (vendor/oniguruma).

pkg_name=jq
pkg_version=1.8.2
pkg_tarball=jq-1.8.2.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() {
  # Docs need pipenv/Python modules: use the shipped jq.1.prebuilt.
  ./configure --prefix=/usr \
              --disable-static \
              --disable-docs \
              --with-oniguruma=builtin \
              --docdir=/usr/share/doc/jq-1.8.2
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
  [[ -x ${dest}/usr/bin/jq ]] || die "jq missing after install"
}
