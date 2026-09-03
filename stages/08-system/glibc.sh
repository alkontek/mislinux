# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.5 Glibc-2.44 (final)
pkg_name=glibc
pkg_version=2.44
pkg_tarball=glibc-2.44.tar.xz
pkg_patches="glibc-fhs-1.patch glibc-2.44-upstream_fixes-1.patch"
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build

pkg_pre_configure() {
  echo "rootsbindir=/usr/sbin" > configparms
}

pkg_configure() {
  ../configure --prefix=/usr \
               --disable-werror \
               --disable-nscd \
               libc_cv_slibdir=/usr/lib \
               --enable-stack-protector=strong \
               --enable-kernel=5.10
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  touch "${dest}/etc/ld.so.conf"
  sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  sed '/RTLDLIST=/s@/usr@@g' -i "${dest}/usr/bin/ldd"
}

pkg_post_install() {
  local dest tzdata ZONEINFO tz
  dest=$(misl_dest)
  mkdir -pv "${dest}/etc"
  printf '%s\n' \
    '# Begin /etc/nsswitch.conf' \
    '' \
    'passwd: files systemd' \
    'group: files systemd' \
    'shadow: files systemd' \
    '' \
    'hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns' \
    'networks: files' \
    '' \
    'protocols: files' \
    'services: files' \
    'ethers: files' \
    'rpc: files' \
    '' \
    '# End /etc/nsswitch.conf' \
    > "${dest}/etc/nsswitch.conf"
  printf '%s\n' \
    '# Begin /etc/ld.so.conf' \
    '/usr/local/lib' \
    '/opt/lib' \
    '' \
    'include /etc/ld.so.conf.d/*.conf' \
    > "${dest}/etc/ld.so.conf"
  mkdir -pv "${dest}/etc/ld.so.conf.d"

  tzdata=$(recipe_require_tarball tzdata2026c.tar.gz)
  tar -xf "$tzdata" -C .
  ZONEINFO=${dest}/usr/share/zoneinfo
  mkdir -pv "$ZONEINFO"/{posix,right}
  for tz in etcetera southamerica northamerica europe africa antarctica \
            asia australasia backward; do
    zic -L /dev/null   -d "$ZONEINFO"       "$tz"
    zic -L /dev/null   -d "$ZONEINFO/posix" "$tz"
    zic -L leapseconds -d "$ZONEINFO/right" "$tz"
  done
  cp -v zone.tab zone1970.tab iso3166.tab "$ZONEINFO"
  zic -d "$ZONEINFO" -p America/New_York

  localedef -i C -f UTF-8 C.UTF-8 || true
  localedef -i en_US -f ISO-8859-1 en_US || true
  localedef -i en_US -f UTF-8 en_US.UTF-8 || true
  localedef -i en_GB -f UTF-8 en_GB.UTF-8 || true
  localedef -i de_DE -f UTF-8 de_DE.UTF-8 || true
  localedef -i fr_FR -f UTF-8 fr_FR.UTF-8 || true
  localedef -i he_IL -f UTF-8 he_IL.UTF-8 || true
}
