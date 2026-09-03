# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.77 Systemd-261.2
# Needs meson + ninja in PATH (chapter 8 recipes).
pkg_name=systemd
pkg_version=261.2
pkg_tarball=systemd-261.2.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=build

pkg_pre_configure() {
  command -v meson >/dev/null 2>&1 || die "systemd needs meson (build meson first)"
  command -v ninja >/dev/null 2>&1 || die "systemd needs ninja (build ninja first)"
}

pkg_configure() {
  meson setup .. \
    --prefix=/usr \
    --libdir=/usr/lib \
    --buildtype=release \
    -D default-dnssec=no \
    -D firstboot=false \
    -D install-tests=false \
    -D ldconfig=false \
    -D sysusers=false \
    -D rpmmacrosdir=no \
    -D homed=disabled \
    -D man=disabled \
    -D mode=release \
    -D pamconfdir=no \
    -D dev-kvm-mode=0660 \
    -D nobody-group=nogroup \
    -D sysupdate=disabled \
    -D ukify=disabled \
    -D docdir=/usr/share/doc/systemd-261.2
}

pkg_build() { ninja; }

pkg_install() {
  local dest manpages
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    DESTDIR="$dest" ninja install
  else
    ninja install
  fi
  manpages=$(recipe_find_tarball systemd-man-pages-261.2.tar.xz || true)
  if [[ -n ${manpages:-} ]]; then
    mkdir -pv "${dest}/usr/share/man"
    tar -xf "$manpages" --no-same-owner --strip-components=1 \
      -C "${dest}/usr/share/man"
  fi
}

pkg_post_install() {
  if command -v systemd-machine-id-setup >/dev/null 2>&1; then
    systemd-machine-id-setup || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl preset-all || true
  fi
  if [[ ! -f /usr/lib/pkgconfig/libsystemd.pc ]]; then
    mkdir -pv /usr/lib/pkgconfig
    cat > /usr/lib/pkgconfig/libsystemd.pc <<'EOF'
prefix=/usr
libdir=${prefix}/lib
includedir=${prefix}/include
Name: systemd
Description: systemd Client Library
Version: 261.2
Libs: -L${libdir} -lsystemd
Cflags: -I${includedir}
EOF
  fi
}
