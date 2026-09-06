# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# hwdata-0.412: pci.ids, usb.ids, oui/iab, pnp.ids into /usr/share/hwdata.
# IDs only: no modprobe blacklist (--disable-blacklist).

pkg_name=hwdata
pkg_version=0.412
pkg_tarball=hwdata-0.412.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() { ./configure --prefix=/usr --disable-blacklist; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  # Do not let make regenerate ids (needs network/rpm); install only.
  make DESTDIR="$dest" install
  rm -f "${dest}/usr/lib/modprobe.d/dist-blacklist.conf"
}

pkg_check() {
  local dest f
  dest=$(misl_dest)
  for f in pci.ids usb.ids pnp.ids oui.txt; do
    [[ -s ${dest}/usr/share/hwdata/$f ]] || die "hwdata $f missing"
  done
}
