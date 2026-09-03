# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd pip package jinja2
pkg_name=jinja2
pkg_version=3.1.6
pkg_tarball=jinja2-3.1.6.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
}
pkg_install() {
  pip3 install --no-index --no-user --find-links dist Jinja2
}
