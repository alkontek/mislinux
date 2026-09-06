# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# glib-2.90.1: GLib/GObject/GIO for bluez (and later desktop work).
# meson >= 1.4.0 required; 08-system ships meson 1.12.0. No docs,
# man pages, introspection, sysprof or tests. Wraps never download:
# gvdb is bundled in subprojects/; pcre2, libffi, zlib come from 08.

pkg_name=glib
pkg_version=2.90.1
pkg_tarball=glib-2.90.1.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="meson ninja python packaging pcre2 libffi zlib util-linux"

pkg_configure() {
  meson setup build --prefix=/usr --libdir=/usr/lib --buildtype=release \
    --wrap-mode=nodownload \
    -D man-pages=disabled \
    -D documentation=false \
    -D introspection=disabled \
    -D sysprof=disabled \
    -D tests=false \
    -D installed_tests=false \
    -D selinux=disabled \
    -D libmount=enabled
}

pkg_build() { ninja -C build ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    DESTDIR="$dest" ninja -C build install
  else
    ninja -C build install
  fi
  [[ -f ${dest}/usr/lib/pkgconfig/glib-2.0.pc ]] || die "glib-2.0.pc missing after install"
}

pkg_check() {
  local dest
  dest=$(misl_dest)
  for l in libglib-2.0 libgobject-2.0 libgio-2.0; do
    compgen -G "${dest}/usr/lib/${l}.so*" >/dev/null || die "$l missing"
  done
  misl_check_run /usr/bin/gio version
}
