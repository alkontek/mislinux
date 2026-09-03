# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Destructive helpers. Dry-run unless MISL_DRY_RUN=0 and confirm is set.
# 0.2 apply is policy A: gates + plan only. parted/mkfs/mount stay operator-run.

# Partition node for DISK + index.
#   /dev/sda                  → /dev/sdaN
#   /dev/nvme0n1|/dev/mmcblk0 → /dev/nvme0n1pN
#   /dev/disk/by-id/FOO       → /dev/disk/by-id/FOO-partN  (udev)
misl_disk_part() {
  local disk=$1 n=$2
  [[ -n $disk && -n $n ]] || die "misl_disk_part: disk and index required"
  case $disk in
    /dev/disk/by-id/*|/dev/disk/by-path/*|/dev/disk/by-uuid/*|/dev/disk/by-label/*|/dev/disk/by-partlabel/*|/dev/disk/by-partuuid/*)
      printf '%s-part%s\n' "$disk" "$n"
      ;;
    /dev/nvme[0-9]*n[0-9]*|/dev/mmcblk[0-9]*|/dev/loop[0-9]*|/dev/nbd[0-9]*|/dev/md[0-9]*)
      printf '%sp%s\n' "$disk" "$n"
      ;;
    *)
      printf '%s%s\n' "$disk" "$n"
      ;;
  esac
}

# Real device node, if the path exists. Used only for host-disk compare.
misl_disk_realpath() {
  local p=$1
  if [[ -e $p ]] && command -v readlink >/dev/null 2>&1; then
    readlink -f "$p" 2>/dev/null || printf '%s\n' "$p"
  else
    printf '%s\n' "$p"
  fi
}

misl_host_disk() {
  local src parent
  src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  [[ -n $src ]] || { printf '%s\n' ""; return 0; }
  if command -v lsblk >/dev/null 2>&1; then
    parent=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
    if [[ -n $parent ]]; then
      printf '/dev/%s\n' "$parent"
      return 0
    fi
  fi
  printf '%s\n' "$src"
}

# Target firmware. Default is EFI even on a BIOS VPS host.
# auto follows the host; bios keeps the GPT bios_grub + ext4 /boot plan.
misl_firmware_resolve() {
  local want=${MISL_FIRMWARE:-efi}
  case ${want,,} in
    auto)
      if [[ -d /sys/firmware/efi ]]; then
        MISL_FIRMWARE=efi
      else
        MISL_FIRMWARE=bios
      fi
      ;;
    efi|uefi) MISL_FIRMWARE=efi ;;
    bios) MISL_FIRMWARE=bios ;;
    *) die "MISL_FIRMWARE=$want (want efi|bios|auto)" ;;
  esac
  export MISL_FIRMWARE
}

# EFI: 1 GiB FAT32 ESP at $LFS/boot/efi (later EFI/misl) + ext4 root.
# BIOS: 1 MiB bios_grub + 1 GiB ext4 /boot + ext4 root. No swap.
misl_disk_resolve_parts() {
  [[ -n ${MISL_DISK:-} ]] || die "MISL_DISK is not set"
  misl_firmware_resolve
  if [[ $MISL_FIRMWARE == efi ]]; then
    [[ -n ${MISL_PART_BOOT:-} ]] || MISL_PART_BOOT=$(misl_disk_part "$MISL_DISK" 1)
    [[ -n ${MISL_PART_ROOT:-} ]] || MISL_PART_ROOT=$(misl_disk_part "$MISL_DISK" 2)
  else
    MISL_PART_BIOSGRUB=$(misl_disk_part "$MISL_DISK" 1)
    export MISL_PART_BIOSGRUB
    [[ -n ${MISL_PART_BOOT:-} ]] || MISL_PART_BOOT=$(misl_disk_part "$MISL_DISK" 2)
    [[ -n ${MISL_PART_ROOT:-} ]] || MISL_PART_ROOT=$(misl_disk_part "$MISL_DISK" 3)
  fi
  export MISL_PART_BOOT MISL_PART_ROOT
}

misl_disk_plan() {
  [[ -n ${MISL_DISK:-} ]] || die "MISL_DISK is not set"
  local host host_real disk_real boot_end
  host=$(misl_host_disk)
  host_real=$(misl_disk_realpath "$host")
  disk_real=$(misl_disk_realpath "$MISL_DISK")
  misl_disk_resolve_parts
  boot_end=$((1 + MISL_BOOT_MIB))

  info "MISL_DISK=$MISL_DISK"
  info "MISL_DISK realpath=$disk_real"
  info "host root disk=$host realpath=$host_real"
  info "LFS=${LFS:-unset}"
  info "fstype=$MISL_FSTYPE dry_run=$MISL_DRY_RUN firmware=$MISL_FIRMWARE boot=${MISL_BOOT_MIB}MiB"
  info "MISL_PART_BOOT=${MISL_PART_BOOT:-none} MISL_PART_ROOT=$MISL_PART_ROOT"
  if [[ -e $MISL_DISK ]]; then
    if command -v lsblk >/dev/null 2>&1; then
      info "lsblk: $(lsblk -dn -o NAME,SIZE,TYPE,TRAN "$MISL_DISK" 2>/dev/null | tr -s ' ' || true)"
    fi
  else
    warn "MISL_DISK does not exist on this host yet — plan is still printed"
  fi
  if [[ -n $host_real && -n $disk_real && $host_real == "$disk_real" ]]; then
    warn "MISL_DISK is the host root disk — apply will refuse unless MISL_ALLOW_HOST_DISK=1"
  fi

  if [[ $MISL_FIRMWARE == efi ]]; then
    info "firmware=efi → gpt + p1 ${MISL_BOOT_MIB}MiB vfat ESP (/boot/efi, later EFI/misl) + p2 $MISL_FSTYPE root. no swap."
    cat <<EOF
# plan only — 0.2 does not execute these
# parted -s $MISL_DISK mklabel gpt
# parted -s $MISL_DISK mkpart ESP fat32 1MiB ${boot_end}MiB
# parted -s $MISL_DISK set 1 esp on
# parted -s $MISL_DISK mkpart root $MISL_FSTYPE ${boot_end}MiB 100%
# udevadm settle
# mkfs.vfat -F32 $MISL_PART_BOOT
# mkfs.$MISL_FSTYPE -L misl $MISL_PART_ROOT
# mkdir -p \$LFS && mount $MISL_PART_ROOT \$LFS
# mkdir -p \$LFS/boot/efi && mount $MISL_PART_BOOT \$LFS/boot/efi
EOF
  else
    local boot_start=2
    boot_end=$((boot_start + MISL_BOOT_MIB))
    info "firmware=bios → gpt + p1 bios_grub + p2 ${MISL_BOOT_MIB}MiB $MISL_FSTYPE /boot + p3 $MISL_FSTYPE root. no swap."
    cat <<EOF
# plan only — 0.2 does not execute these
# parted -s $MISL_DISK mklabel gpt
# parted -s $MISL_DISK mkpart bios_grub 1MiB ${boot_start}MiB
# parted -s $MISL_DISK set 1 bios_grub on
# parted -s $MISL_DISK mkpart boot $MISL_FSTYPE ${boot_start}MiB ${boot_end}MiB
# parted -s $MISL_DISK mkpart root $MISL_FSTYPE ${boot_end}MiB 100%
# udevadm settle
# mkfs.$MISL_FSTYPE -L mislboot $MISL_PART_BOOT
# mkfs.$MISL_FSTYPE -L misl $MISL_PART_ROOT
# mkdir -p \$LFS && mount $MISL_PART_ROOT \$LFS
# mkdir -p \$LFS/boot && mount $MISL_PART_BOOT \$LFS/boot
EOF
  fi
}

misl_disk_apply() {
  require_root
  [[ -n ${MISL_DISK:-} ]] || die "MISL_DISK is not set"
  [[ ${MISL_CONFIRM:-} == YES-DESTROY-DISK ]] || die "refusing apply: set MISL_CONFIRM=YES-DESTROY-DISK"
  [[ ${MISL_DRY_RUN:-1} == 0 ]] || die "refusing apply: set MISL_DRY_RUN=0 after reviewing 'misl disk plan'"
  require_lfs_set
  local host host_real disk_real
  host=$(misl_host_disk)
  host_real=$(misl_disk_realpath "$host")
  disk_real=$(misl_disk_realpath "$MISL_DISK")
  if [[ -n $host_real && -n $disk_real && $host_real == "$disk_real" && ${MISL_ALLOW_HOST_DISK:-0} != 1 ]]; then
    die "MISL_DISK=$MISL_DISK ($disk_real) backs the host root; set MISL_ALLOW_HOST_DISK=1 to override"
  fi
  misl_disk_plan
  die "0.2 disk apply stops after gates+plan (policy A). Partition and mount \$LFS by hand."
}
