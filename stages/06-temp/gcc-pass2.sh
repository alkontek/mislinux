# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §6.18 GCC-16.2.0 pass 2
pkg_name=gcc
pkg_version=16.2.0
pkg_tarball=gcc-16.2.0.tar.xz
pkg_patches=
pkg_stage=06-temp
pkg_pass=2
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
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' -i.orig "$src/gcc/config/i386/t-linux64"
      ;;
  esac
}

pkg_configure() {
  ../configure --build="$(../config.guess)" \
               --host="$LFS_TGT" \
               --target="$LFS_TGT" \
               --prefix=/usr \
               --with-build-sysroot="$LFS" \
               --enable-default-pie \
               --enable-default-ssp \
               --disable-fixincludes \
               --disable-nls \
               --disable-multilib \
               --disable-libatomic \
               --disable-libgomp \
               --disable-libquadmath \
               --disable-libsanitizer \
               --disable-libssp \
               --disable-libvtv \
               --enable-languages=c,c++ \
               CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++" \
               LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc" \
               target_configargs=gcc_cv_target_thread_file=posix
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  misl_make_install DESTDIR="$LFS" install
  ln -sfv gcc "$LFS/usr/bin/cc"
}
