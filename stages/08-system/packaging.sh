# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd pip package packaging
pkg_name=packaging
pkg_version=26.3
pkg_tarball=packaging-26.3.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
}
pkg_install() {
  pip3 install --no-index --no-user --find-links dist packaging
}
