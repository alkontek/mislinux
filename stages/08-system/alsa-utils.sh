# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# alsa-utils-1.2.16: alsactl, amixer, alsamixer, aplay, speaker-test...
# No man pages (xmlto/rst2man), no alsaconf, no bat (fftw). alsactl
# restore/store units and 90-alsa-restore.rules into systemd paths.

pkg_name=alsa-utils
pkg_version=1.2.16
pkg_tarball=alsa-utils-1.2.16.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="alsa-lib ncurses systemd"

pkg_configure() {
  ./configure --prefix=/usr --sysconfdir=/etc \
    --disable-alsaconf --disable-bat \
    --disable-xmlto --disable-rst2man \
    --with-curses=ncursesw \
    --with-systemdsystemunitdir=/usr/lib/systemd/system \
    --with-udev-rules-dir=/usr/lib/udev/rules.d
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  make DESTDIR="$dest" install
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -f ${dest}/usr/lib/systemd/system/alsa-restore.service ]] || die "alsa-restore.service missing"
  [[ -f ${dest}/usr/lib/udev/rules.d/90-alsa-restore.rules ]] || die "alsa udev rules missing"
  misl_check_run /usr/sbin/alsactl --version
}
