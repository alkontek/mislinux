# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# lm-sensors-3.6.2 (upstream tag V3-6-2, top dir lm-sensors-3-6-2).
# libsensors + sensors; no sensord (rrdtool), no static lib.

pkg_name=lm-sensors
pkg_version=3.6.2
pkg_tarball=lm-sensors-3.6.2.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="flex bison"

_lm_sensors_make() {
  make PREFIX=/usr MANDIR=/usr/share/man BUILD_STATIC_LIB=0 PROG_EXTRA= "$@"
}

pkg_build() { _lm_sensors_make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  _lm_sensors_make DESTDIR="$dest" install
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  [[ -x ${dest}/usr/bin/sensors ]] || die "sensors missing"
  [[ ! -e ${dest}/usr/sbin/sensord ]] || die "sensord built unexpectedly"
  misl_check_run /usr/bin/sensors --version
}
