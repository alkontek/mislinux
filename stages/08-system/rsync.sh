# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# rsync-3.5.0: included popt, no xxhash; system zlib/zstd/lz4/openssl.

pkg_name=rsync
pkg_version=3.5.0
pkg_tarball=rsync-3.5.0.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="zlib zstd lz4 openssl acl attr"

pkg_configure() {
  # popt is not in the graph: rsync falls back to its included copy.
  ./configure --prefix=/usr \
              --disable-xxhash \
              --without-included-zlib \
              --with-included-popt
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
  [[ -x ${dest}/usr/bin/rsync ]] || die "rsync missing after install"
}
