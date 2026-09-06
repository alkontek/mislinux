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
  local dest root_dev boot_dev root_uuid root_partuuid root_src kver cmdline cmd_plain efi_dir
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
  root_uuid='' root_partuuid='' root_src=''
  if command -v blkid >/dev/null 2>&1; then
    if [[ -n $root_dev && -e $root_dev ]]; then
      root_uuid=$(blkid -s UUID -o value "$root_dev" || true)
      root_src=$root_dev
    fi
    if [[ -z $root_uuid ]]; then
      local src
      src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
      [[ -n $src && -e $src ]] && root_uuid=$(blkid -s UUID -o value "$src" || true)
      root_src=$src
    fi
    [[ -n $root_src ]] && root_partuuid=$(blkid -s PARTUUID -o value "$root_src" || true)
  fi
  # Never guess a kernel name (/dev/sdaN). Wrong disk is worse than fail.
  [[ -n $root_uuid ]] || \
    die "no root UUID (blkid on MISL_PART_ROOT or findmnt /). set MISL_PART_ROOT to a device visible in this chroot"
  # root=UUID= (filesystem UUID) needs the initramfs; the kernel alone
  # only resolves PARTUUID=. The "(no initramfs)" entry uses PARTUUID.
  cmdline="root=UUID=${root_uuid} ro rootfstype=${MISL_FSTYPE:-ext4}"
  if [[ -n $root_partuuid ]]; then
    cmd_plain="root=PARTUUID=${root_partuuid} ro rootfstype=${MISL_FSTYPE:-ext4}"
  else
    warn "no PARTUUID for the root; the no-initramfs entry keeps root=UUID= and will not find root"
    cmd_plain=$cmdline
  fi

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

  misl_initramfs_auto "$dest" "$kver"

  mkdir -pv "${dest}/boot/grub"
  {
    printf '%s\n' 'set default=0' 'set timeout=5' 'insmod part_gpt' 'insmod ext2' 'insmod fat'
    printf 'search --no-floppy --fs-uuid --set=root %s\n' "${root_uuid:-}"
    misl_initramfs_grub_entries "$dest" /boot "$kver" \
      "${MISL_PRETTY_NAME:-MIS Linux $MISL_VERSION}" "$cmdline" "$cmd_plain"
  } > "${dest}/boot/grub/grub.cfg"
  info "wrote /boot/grub/grub.cfg and EFI/misl (firmware=${MISL_FIRMWARE:-efi})"
}
