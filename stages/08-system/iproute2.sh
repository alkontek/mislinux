# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.67 IPRoute2-7.1.0
pkg_name=iproute2
pkg_version=7.1.0
pkg_tarball=iproute2-7.1.0.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_pre_configure() { sed -i /ARPD/d Makefile; rm -fv man/man8/arpd.8; }
pkg_configure() { :; }
pkg_build() { make NETNS_RUN_DIR=/run/netns ${MISL_MAKEFLAGS:-}; }
pkg_install() {
  local dest; dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make SBINDIR=/usr/sbin DESTDIR="$dest" install
  else
    make SBINDIR=/usr/sbin install
  fi
}
