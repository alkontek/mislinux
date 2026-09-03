# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.30 Shadow-4.20.2
# Does not run passwd interactively; set root password in 09-config.
pkg_name=shadow
pkg_version=4.20.2
pkg_tarball=shadow-4.20.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() {
  sed -i "s/groups$(EXEEXT) //" src/Makefile.in
  find man -name Makefile.in -exec sed -i "s/groups\.1 / /" {} +
  find man -name Makefile.in -exec sed -i "s/getspnam\.3 / /" {} +
  find man -name Makefile.in -exec sed -i "s/passwd\.5 / /" {} +
  sed -e "s:#ENCRYPT_METHOD SHA512:ENCRYPT_METHOD YESCRYPT:" \
      -e "s:/var/spool/mail:/var/mail:" \
      -e "/PATH=/{s@/sbin:@@;s@/bin:@@}" \
      -i etc/login.defs
}
pkg_configure() {
  ./configure --sysconfdir=/etc \
              --disable-static \
              --with-{b,yes}crypt \
              --without-libbsd \
              --disable-logind \
              --with-group-name-max-length=32
}
pkg_build() { make ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make exec_prefix=/usr DESTDIR="$dest" install
    make -C man DESTDIR="$dest" install-man
  else
    make exec_prefix=/usr install
    make -C man install-man
  fi
  pwconv || true
  grpconv || true
  mkdir -p "${dest}/etc/default"
  useradd -D --gid 999 || true
}
