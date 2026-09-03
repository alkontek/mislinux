# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.78 D-Bus-1.16.2
pkg_name=dbus
pkg_version=1.16.2
pkg_tarball=dbus-1.16.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build

pkg_pre_configure() {
  command -v meson >/dev/null 2>&1 || die "dbus needs meson (build meson first)"
  command -v ninja >/dev/null 2>&1 || die "dbus needs ninja (build ninja first)"
}

pkg_configure() {
  meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
}

pkg_build() { ninja; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    DESTDIR="$dest" ninja install
  else
    ninja install
  fi
  mkdir -pv "${dest}/var/lib/dbus"
  ln -sfv /etc/machine-id "${dest}/var/lib/dbus"
}
