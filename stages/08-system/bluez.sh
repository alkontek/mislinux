# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# bluez-5.87: bluetoothd, bluetoothctl, btmon. Needs glib >= 2.36,
# dbus >= 1.10, libudev (systemd), readline (client). No OBEX (libical),
# mesh (ell/json-c), MIDI (alsa), CUPS or man pages (rst2man).

pkg_name=bluez
pkg_version=5.87
pkg_tarball=bluez-5.87.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="glib dbus systemd readline"

pkg_configure() {
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    --disable-obex --disable-manpages --disable-mesh --disable-midi \
    --disable-cups --enable-library \
    --with-systemdsystemunitdir=/usr/lib/systemd/system \
    --with-systemduserunitdir=/usr/lib/systemd/user \
    --with-udevdir=/usr/lib/udev
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  make DESTDIR="$dest" install
  # bluetoothd lives in libexec; /usr/sbin link for operators.
  install -v -d -m755 "${dest}/usr/sbin" "${dest}/etc/bluetooth"
  ln -sfv ../libexec/bluetooth/bluetoothd "${dest}/usr/sbin/bluetoothd"
  [[ -f ${dest}/etc/bluetooth/main.conf ]] || install -v -m644 src/main.conf "${dest}/etc/bluetooth/main.conf"
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -f ${dest}/usr/lib/systemd/system/bluetooth.service ]] || die "bluetooth.service missing"
  [[ -x ${dest}/usr/bin/bluetoothctl ]] || die "bluetoothctl missing"
  misl_check_run /usr/libexec/bluetooth/bluetoothd --version
}
