# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.81 Util-linux-2.42.2 (final)
pkg_name=util-linux
pkg_version=2.42.2
pkg_tarball=util-linux-2.42.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() { mkdir -pv /var/lib/hwclock; }
pkg_configure() {
  ./configure --bindir=/usr/bin \
              --libdir=/usr/lib \
              --runstatedir=/run \
              --sbindir=/usr/sbin \
              --disable-chfn-chsh \
              --disable-login \
              --disable-nologin \
              --disable-su \
              --disable-setpriv \
              --disable-runuser \
              --disable-pylibmount \
              --disable-liblastlog2 \
              --disable-static \
              --without-python \
              ADJTIME_PATH=/var/lib/hwclock/adjtime \
              --docdir=/usr/share/doc/util-linux-2.42.2
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
}
