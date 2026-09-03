# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §8.65 GRUB-2.14
# Install i386-pc and x86_64-efi modules. 10-boot picks the target.
pkg_name=grub
pkg_version=2.14
pkg_tarball=grub-2.14.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree

pkg_pre_configure() {
  echo "depends bli part_gpt" > grub-core/extra_deps.lst
}

pkg_configure() {
  ./configure --prefix=/usr --sysconfdir=/etc \
              --disable-efiemu --disable-werror \
              --with-platform=efi --target=x86_64
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi

  # BIOS modules as well (VPS / fallback). Rebuild in-tree for i386-pc.
  make distclean >/dev/null 2>&1 || make clean || true
  echo "depends bli part_gpt" > grub-core/extra_deps.lst
  ./configure --prefix=/usr --sysconfdir=/etc \
              --disable-efiemu --disable-werror \
              --with-platform=pc --target=i386
  make ${MISL_MAKEFLAGS:-}
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi

  local efi_mod=${dest}/usr/lib/grub/x86_64-efi/modinfo.sh
  [[ -f $efi_mod ]] || die "GRUB EFI modules missing at $efi_mod"
}
