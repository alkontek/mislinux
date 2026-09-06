# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# usbutils-020: lsusb, lsusb.py, usb-devices, usbhid-dump, usbreset.
# lsusb resolves names via the udev hwdb; lsusb.py reads
# /usr/share/hwdata/usb.ids from hwdata.

pkg_name=usbutils
pkg_version=020
pkg_tarball=usbutils-020.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="libusb hwdata systemd meson ninja"

pkg_configure() { meson setup build --prefix=/usr --libdir=/usr/lib --buildtype=release; }

pkg_build() { ninja -C build ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    DESTDIR="$dest" ninja -C build install
  else
    ninja -C build install
  fi
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -x ${dest}/usr/bin/lsusb ]] || die "lsusb missing"
  [[ -s ${dest}/usr/share/hwdata/usb.ids || -s /usr/share/hwdata/usb.ids ]] || die "usb.ids missing (hwdata)"
  misl_check_run lsusb
}
