# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Overlay $MISL_ROOT/usr/bin onto the target /usr/bin (no tarball).
pkg_name=usr-bin
pkg_version=0.2
pkg_tarball=-
pkg_patches=
pkg_stage=09-config
pkg_pass=1
pkg_unpack=no
pkg_builddir=in-tree

pkg_configure() { :; }
pkg_build() { :; }

pkg_install() {
  local dest src f base
  dest=$(misl_dest)
  src=$MISL_ROOT/usr/bin
  [[ -d $src ]] || die "overlay missing: $src"
  install -d -m755 "${dest}/usr/bin"
  shopt -s nullglob
  for f in "$src"/*; do
    [[ -f $f ]] || continue
    base=$(basename "$f")
    install -m755 "$f" "${dest}/usr/bin/$base"
    info "overlay /usr/bin/$base"
  done
  [[ -x ${dest}/usr/bin/stardate ]] || die "stardate missing after overlay"
}
