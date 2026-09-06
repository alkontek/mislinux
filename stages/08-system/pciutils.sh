# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# pciutils-3.15.0: lspci/setpci + shared libpci. pci.ids comes from
# hwdata (/usr/share/hwdata); update-pciids is not installed.

pkg_name=pciutils
pkg_version=3.15.0
pkg_tarball=pciutils-3.15.0.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="hwdata zlib"

_pciutils_make() {
  # ZLIB=no: hwdata ships plain pci.ids, not pci.ids.gz.
  make PREFIX=/usr SHAREDIR=/usr/share/hwdata IDSDIR=/usr/share/hwdata \
       MANDIR=/usr/share/man SHARED=yes ZLIB=no "$@"
}

pkg_build() { _pciutils_make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest hw
  dest=$(misl_dest)
  # make install copies ./pci.ids over IDSDIR; feed it hwdata's copy so
  # the newer hwdata file is what lands there.
  hw=${dest}/usr/share/hwdata/pci.ids
  [[ -f $hw ]] || hw=/usr/share/hwdata/pci.ids
  [[ -f $hw ]] || die "pciutils needs hwdata pci.ids"
  cp -v "$hw" pci.ids
  _pciutils_make DESTDIR="$dest" install install-lib
  chmod -v 755 "${dest}"/usr/lib/libpci.so.*
  rm -fv "${dest}/usr/sbin/update-pciids" "${dest}/usr/share/man/man8/update-pciids.8"
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -x ${dest}/usr/sbin/lspci || -x ${dest}/usr/bin/lspci ]] || die "lspci missing"
  [[ ! -e ${dest}/usr/sbin/update-pciids ]] || die "update-pciids installed"
  misl_check_run lspci -nn
}
