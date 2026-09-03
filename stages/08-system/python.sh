# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.54 Python-3.14.7
pkg_name=python
pkg_version=3.14.7
pkg_tarball=Python-3.14.7.tar.xz
pkg_patches=Python-3.14.7-openssl_4-1.patch
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() {
  ./configure --prefix=/usr --enable-shared --with-system-expat --enable-optimizations --without-static-libpython
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest docs
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  docs=$(recipe_find_tarball python-3.14.7-docs-html.tar.bz2 || true)
  if [[ -n ${docs:-} ]]; then
    install -v -dm755 "${dest}/usr/share/doc/python-3.14.7/html"
    tar --strip-components=1 --no-same-owner --no-same-permissions \
      -C "${dest}/usr/share/doc/python-3.14.7/html" -xf "$docs"
  fi
}
