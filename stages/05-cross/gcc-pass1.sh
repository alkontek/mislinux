# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §5.3 GCC-16.2.0 pass 1
pkg_name=gcc
pkg_version=16.2.0
pkg_tarball=gcc-16.2.0.tar.xz
pkg_patches=
pkg_stage=05-cross
pkg_pass=1
pkg_builddir=build

pkg_pre_configure() {
  local src dep tarball dest path
  src=$(cd .. && pwd)
  for dep in mpfr-4.2.2.tar.xz:mpfr gmp-6.3.0.tar.xz:gmp mpc-1.4.1.tar.xz:mpc; do
    tarball=${dep%%:*}
    dest=${dep##*:}
    path=$(recipe_require_tarball "$tarball")
    info "unpack $tarball -> $dest"
    tar -xf "$path" -C "$src"
    mv "$src/${tarball%.tar.*}" "$src/$dest"
  done
}

pkg_configure() {
  ../configure --target="$LFS_TGT" \
               --prefix="$LFS/tools" \
               --with-glibc-version=2.44 \
               --with-sysroot="$LFS" \
               --with-newlib \
               --without-headers \
               --enable-default-pie \
               --enable-default-ssp \
               --disable-fixincludes \
               --disable-nls \
               --disable-shared \
               --disable-multilib \
               --disable-threads \
               --disable-libatomic \
               --disable-libgomp \
               --disable-libquadmath \
               --disable-libssp \
               --disable-libvtv \
               --disable-libstdcxx \
               --enable-languages=c,c++
}

pkg_build() {
  # shellcheck disable=SC2086
  make ${MISL_MAKEFLAGS:-}
}

pkg_install() {
  local cc inc
  misl_ensure_dir "$LFS/tools/bin"
  misl_make_install install
  cc=$LFS/tools/bin/$LFS_TGT-gcc
  [[ -x $cc ]] || die "missing $cc after gcc pass1 install"
  inc=$("$cc" -print-file-name=include)
  [[ -n $inc && $inc != include ]] || die "$cc -print-file-name=include failed"
  cat ../gcc/{limitx,glimits,limity}.h >"$inc/limits.h"
}
