# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# libusb-1.0.30: userspace USB library (usbutils). udev hotplug.

pkg_name=libusb
pkg_version=1.0.30
pkg_tarball=libusb-1.0.30.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="systemd"

pkg_configure() { ./configure --prefix=/usr --disable-static --enable-udev; }

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  make DESTDIR="$dest" install
  [[ -f ${dest}/usr/lib/pkgconfig/libusb-1.0.pc ]] || die "libusb-1.0.pc missing"
}
