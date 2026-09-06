# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# linux-firmware-20261019: staged, not installed.
#
# The tree goes to /usr/share/misl/linux-firmware (copy-firmware.sh
# resolves WHENCE links; uncompressed). Nothing lands in /lib/firmware
# here: overlays copy only what their firmware.list names (plan-0.4
# item 5). The kernel never loads from the staging dir.

pkg_name=linux-firmware
pkg_version=20261019
pkg_tarball=linux-firmware-20261019.tar.xz
pkg_patches=
pkg_stage=10-boot
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="python"

MISL_FIRMWARE_STAGE=/usr/share/misl/linux-firmware

pkg_pre_configure() {
  command -v python3 >/dev/null 2>&1 || die "linux-firmware needs python3 (check_whence.py)"
  [[ -x ./copy-firmware.sh && -f WHENCE ]] || die "linux-firmware tarball has no copy-firmware.sh/WHENCE"
}

pkg_configure() { :; }
pkg_build() { :; }

pkg_install() {
  local dest stage
  dest=$(misl_dest)
  stage=${dest}${MISL_FIRMWARE_STAGE}
  rm -rf "$stage"
  install -v -d -m755 "$stage"
  # -j1: GNU parallel is not in the graph.
  ./copy-firmware.sh -j1 "$stage"
  install -v -m644 WHENCE LICENCE.* LICENSE.* "$stage/" 2>/dev/null || true
  printf '%s\n' "$pkg_version" > "$stage/.misl-version"
  [[ -f $stage/WHENCE ]] || die "linux-firmware staging failed: $stage"
  info "linux-firmware staged at ${MISL_FIRMWARE_STAGE} ($(du -sh "$stage" | cut -f1)); /lib/firmware untouched"
}
