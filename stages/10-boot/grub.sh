# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# GRUB to /boot/efi/EFI/misl plus removable fallback.
pkg_name=grub
pkg_version=2.14
pkg_tarball=-
pkg_patches=
pkg_stage=10-boot
pkg_pass=1
pkg_unpack=no
pkg_builddir=in-tree

pkg_configure() { :; }
pkg_build() { :; }

pkg_install() {
  local dest root_dev boot_dev root_uuid kver cmdline efi_dir
  dest=$(misl_dest)
  kver=7.1.8-misl
  command -v grub-install >/dev/null 2>&1 || die "grub-install missing (build 08-system/grub first)"

  # Host by-id path is often unset or invisible in the chroot. Do not
  # die — EFI grub-install only needs /boot/efi. Same as 09-config.
  if ! misl_disk_resolve_parts; then
    info "MISL_DISK unset in chroot; grub.cfg root= from findmnt/blkid"
  fi
  root_dev=${MISL_PART_ROOT:-}
  boot_dev=${MISL_PART_BOOT:-}
  root_uuid=
  if command -v blkid >/dev/null 2>&1; then
    [[ -n $root_dev && -e $root_dev ]] && \
      root_uuid=$(blkid -s UUID -o value "$root_dev" || true)
    if [[ -z $root_uuid ]]; then
      local src
      src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
      [[ -n $src && -e $src ]] && root_uuid=$(blkid -s UUID -o value "$src" || true)
    fi
  fi
  # Never guess a kernel name (/dev/sdaN). Wrong disk is worse than fail.
  [[ -n $root_uuid ]] || \
    die "no root UUID (blkid on MISL_PART_ROOT or findmnt /). set MISL_PART_ROOT to a device visible in this chroot"
  cmdline="root=UUID=${root_uuid} ro rootfstype=${MISL_FSTYPE:-ext4}"

  mkdir -pv "${dest}/boot/grub" "${dest}/boot/efi"
  efi_dir=/boot/efi
  [[ -d ${dest}${efi_dir} ]] || efi_dir="${dest}/boot/efi"

  if [[ ${MISL_FIRMWARE:-efi} == efi ]]; then
    [[ -f /usr/lib/grub/x86_64-efi/modinfo.sh ]] || \
      die "no x86_64-efi GRUB modules; MISL_FORCE=1 ./misl build 08-system/grub"
    if [[ ! -d /boot/efi/EFI && -n $boot_dev && -e $boot_dev ]]; then
      mkdir -pv /boot/efi
      mountpoint -q /boot/efi || mount "$boot_dev" /boot/efi
    fi
    # Chroot / VPS has no efibootmgr NVRAM. Files go on the ESP;
    # --removable writes EFI/BOOT/BOOTX64.EFI for firmware that ignores Boot####.
    grub-install --target=x86_64-efi \
                 --efi-directory=/boot/efi \
                 --bootloader-id=misl \
                 --recheck --no-nvram
    grub-install --target=x86_64-efi \
                 --efi-directory=/boot/efi \
                 --removable \
                 --recheck --no-nvram
    if command -v efibootmgr >/dev/null 2>&1; then
      efibootmgr --create --disk "${MISL_DISK:-}" --part 1 \
        --loader '\EFI\misl\grubx64.efi' --label MISL || true
    fi
  else
    [[ -n ${MISL_DISK:-} ]] || die "MISL_DISK required for bios grub-install"
    grub-install --target=i386-pc "$MISL_DISK"
  fi

  mkdir -pv "${dest}/boot/grub"
  {
    printf '%s\n' 'set default=0' 'set timeout=5' 'insmod part_gpt' 'insmod ext2' 'insmod fat'
    printf 'search --no-floppy --fs-uuid --set=root %s\n' "${root_uuid:-}"
    printf 'menuentry "%s" {\n' "${MISL_PRETTY_NAME:-MIS Linux $MISL_VERSION}"
    printf '        linux /boot/vmlinuz-%s %s\n' "$kver" "$cmdline"
    printf '}\n'
  } > "${dest}/boot/grub/grub.cfg"
  info "wrote /boot/grub/grub.cfg and EFI/misl (firmware=${MISL_FIRMWARE:-efi})"
}
