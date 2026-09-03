# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §5.5 Glibc-2.44
pkg_name=glibc
pkg_version=2.44
pkg_tarball=glibc-2.44.tar.xz
pkg_patches="glibc-fhs-1.patch glibc-2.44-upstream_fixes-1.patch"
pkg_stage=05-cross
pkg_pass=1
pkg_builddir=build

pkg_pre_configure() {
  case $(uname -m) in
    x86_64)
      ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
      ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
      ;;
  esac
  echo "rootsbindir=/usr/sbin" > configparms
}

pkg_configure() {
  ../configure --prefix=/usr \
               --host="$LFS_TGT" \
               --build="$(../scripts/config.guess)" \
               --enable-kernel=5.10 \
               --with-headers="$LFS/usr/include" \
               --disable-nscd \
               libc_cv_slibdir=/usr/lib
}

pkg_build() {
  # shellcheck disable=SC2086
  make ${MISL_MAKEFLAGS:-}
}

pkg_install() {
  make DESTDIR="$LFS" install
  sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"
}

pkg_post_install() {
  local out
  echo 'int main(){}' | "$LFS_TGT-gcc" -xc -
  out=$("$LFS_TGT-readelf" -l a.out | grep ld-linux || true)
  rm -f a.out
  [[ -n $out ]] || die "glibc sanity check failed (no ld-linux in a.out)"
  info "glibc sanity: $out"
}
