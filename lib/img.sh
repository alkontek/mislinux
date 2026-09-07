# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash

# Pack $LFS into a BIOS GPT .img. Host root, not chroot.
misl_img_default_out() {
  local dir tag=img root
  dir=$(pwd)
  root=${LFS:-}/var/lib/misl/overlays
  if [[ -f $root/do/applied ]]; then
    tag=do
  elif [[ -f $root/cloud/applied ]]; then
    tag=cloud
  fi
  printf '%s/misl-%s-%s.img\n' "$dir" "${MISL_VERSION:-0.3}" "$tag"
}

misl_img_assert_host() {
  require_root
  require_lfs_set
  [[ ${LFS:-} != / ]] || die "img pack runs on the Fedora host. exit the chroot first"
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
}

# Raw copy of MISL_DISK. Keeps whatever firmware the volume already has.
misl_img_from_disk() {
  local out=$1
  [[ -n ${MISL_DISK:-} && -b ${MISL_DISK} ]] || \
    die "MISL_DISK is not a block device (set it or use --from-tree)"
  local host host_real disk_real
  host=$(misl_host_disk)
  host_real=$(misl_disk_realpath "$host")
  disk_real=$(misl_disk_realpath "$MISL_DISK")
  if [[ -n $host_real && -n $disk_real && $host_real == "$disk_real" && ${MISL_ALLOW_HOST_DISK:-0} != 1 ]]; then
    die "refusing to image the host root disk; set MISL_ALLOW_HOST_DISK=1"
  fi
  if [[ ${MISL_FIRMWARE:-efi} == efi ]]; then
    warn "this volume is EFI; DigitalOcean Custom Images require BIOS"
    warn "prefer: ./misl img pack --from-tree  (GPT + bios_grub + ext4)"
  fi
  info "dd $MISL_DISK -> $out (sparse)"
  dd if="$MISL_DISK" of="$out" bs=16M status=progress conv=sparse
}

# New GPT BIOS disk built from the $LFS tree. This is the DO path.
misl_img_from_tree() {
  local out=$1 size_g loop mnt p1 p2 p3 used_m need_m boot_m
  require_cmd parted mkfs.ext4 losetup rsync blkid
  boot_m=${MISL_BOOT_MIB:-1024}
  info "measuring $LFS (excluding tools + usr/src)"
  used_m=0
  # pipefail + du errors (proc, bind mounts) used to abort with no message
  used_m=$(du -sm \
    --exclude="${LFS}/tools" \
    --exclude="${LFS}/usr/src" \
    --exclude="${LFS}/proc" \
    --exclude="${LFS}/sys" \
    --exclude="${LFS}/dev" \
    --exclude="${LFS}/run" \
    "$LFS" 2>/dev/null | awk 'END { print $1 }') || true
  used_m=${used_m:-0}
  need_m=$((used_m + boot_m + 1024))
  size_g=${MISL_IMG_GIB:-}
  if [[ -z $size_g ]]; then
    size_g=$(( (need_m + 1023) / 1024 ))
    if (( size_g < 4 )); then
      size_g=4
    fi
  fi
  info "creating ${size_g}GiB sparse $out (payload ~${used_m}MiB + /boot)"
  rm -f "$out"
  truncate -s "${size_g}G" "$out"

  loop=$(losetup --find --show --partscan "$out")
  [[ -n $loop ]] || die "losetup failed"
  # shellcheck disable=SC2064
  trap 'umount -R "$mnt" 2>/dev/null || true; losetup -d "$loop" 2>/dev/null || true' EXIT

  parted -s "$loop" mklabel gpt
  parted -s "$loop" mkpart bios_grub 1MiB 2MiB
  parted -s "$loop" set 1 bios_grub on
  parted -s "$loop" mkpart boot ext4 2MiB $((2 + boot_m))MiB
  parted -s "$loop" mkpart root ext4 $((2 + boot_m))MiB 100%
  udevadm settle 2>/dev/null || sleep 1
  partprobe "$loop" 2>/dev/null || true
  udevadm settle 2>/dev/null || sleep 1

  p1=${loop}p1
  p2=${loop}p2
  p3=${loop}p3
  [[ -b $p2 && -b $p3 ]] || die "loop partitions missing under $loop (need losetup -P)"
  mkfs.ext4 -F -L mislboot "$p2"
  mkfs.ext4 -F -L misl "$p3"

  mnt=$(mktemp -d /tmp/misl-img.XXXXXX)
  mount "$p3" "$mnt"
  mkdir -pv "$mnt/boot"
  mount "$p2" "$mnt/boot"

  info "rsync $LFS -> image (no /tools, /usr/src)"
  rsync -aHAX --numeric-ids \
    --exclude '/proc/**' --exclude '/sys/**' --exclude '/dev/**' \
    --exclude '/run/**' --exclude '/tmp/**' --exclude '/boot/efi/**' \
    --exclude '/tools/**' --exclude '/usr/src/**' \
    --exclude '/var/tmp/**' --exclude '/var/lib/misl/logs/**' \
    --exclude '/boot/grub/grub.cfg' \
    "$LFS"/ "$mnt"/ || die "rsync failed"

  mkdir -pv "$mnt"/{proc,sys,dev,run,tmp,boot}
  chmod 1777 "$mnt/tmp"

  local root_uuid boot_uuid root_partuuid kver cmdline
  # -p: do not use blkid cache (that cache still has the live $LFS UUID).
  root_uuid=$(blkid -p -s UUID -o value "$p3" 2>/dev/null || true)
  boot_uuid=$(blkid -p -s UUID -o value "$p2" 2>/dev/null || true)
  root_partuuid=$(blkid -p -s PARTUUID -o value "$p3" 2>/dev/null || true)
  [[ -n $root_uuid ]] || root_uuid=$(tune2fs -l "$p3" | awk '/Filesystem UUID/{print $3}')
  [[ -n $boot_uuid ]] || boot_uuid=$(tune2fs -l "$p2" | awk '/Filesystem UUID/{print $3}')
  [[ -n $root_partuuid ]] || root_partuuid=$(blkid -s PARTUUID -o value "$p3")
  [[ -n $root_uuid && -n $boot_uuid && -n $root_partuuid ]] || \
    die "no UUID/PARTUUID on image partitions $p2 $p3"
  kver=7.1.8-misl
  # No initramfs: kernel root=UUID= is not ext4 UUID. Use GPT PARTUUID.
  cmdline="root=PARTUUID=${root_partuuid} ro rootfstype=ext4 console=ttyS0,115200n8 console=tty0"
  info "image fs UUID root=$root_uuid boot=$boot_uuid PARTUUID=$root_partuuid"

  # Kernel lives at $LFS/boot on EFI builds (root) or /boot mount.
  if [[ ! -f $mnt/boot/vmlinuz-$kver ]]; then
    if [[ -f $LFS/boot/vmlinuz-$kver ]]; then
      cp -a "$LFS/boot/vmlinuz-$kver" "$mnt/boot/"
    else
      warn "no vmlinuz-$kver on the image — 10-boot/linux first"
    fi
  fi

  mount --bind /dev "$mnt/dev"
  mount --bind /proc "$mnt/proc"
  mount --bind /sys "$mnt/sys"
  [[ -x $mnt/usr/sbin/grub-install || -x $mnt/usr/bin/grub-install ]] || \
    die "no grub-install in the tree"
  chroot "$mnt" /usr/bin/env -i PATH=/usr/bin:/usr/sbin \
    grub-install --target=i386-pc --recheck "$loop" || \
    die "tree grub-install i386-pc failed. rebuild: MISL_FORCE=1 ./misl build 08-system/grub"

  # Write fstab + grub.cfg AFTER grub-install. --recheck may regenerate
  # grub.cfg from the live $LFS UUID in /etc/default/grub.
  {
    printf '%s\n' '# /etc/fstab — MIS Linux DigitalOcean image'
    printf 'UUID=%s  /      ext4  defaults  1 1\n' "$root_uuid"
    printf 'UUID=%s  /boot  ext4  defaults  1 2\n' "$boot_uuid"
    printf 'proc  /proc  proc  nosuid,noexec,nodev  0 0\n'
    printf 'sysfs /sys   sysfs nosuid,noexec,nodev  0 0\n'
    printf 'devtmpfs /dev devtmpfs mode=0755,nosuid 0 0\n'
  } >"$mnt/etc/fstab"

  mkdir -pv "$mnt/boot/grub"
  {
    printf '%s\n' 'set default=0' 'set timeout=3'
    printf '%s\n' 'insmod part_gpt' 'insmod ext2'
    printf '%s\n' 'serial --unit=0 --speed=115200'
    printf '%s\n' 'terminal_input serial console'
    printf '%s\n' 'terminal_output serial console'
    printf 'search --no-floppy --fs-uuid --set=root %s\n' "$boot_uuid"
    printf 'menuentry "%s" {\n' "${MISL_PRETTY_NAME:-MIS Linux $MISL_VERSION}"
    printf '        linux /vmlinuz-%s %s\n' "$kver" "$cmdline"
    printf '}\n'
  } >"$mnt/boot/grub/grub.cfg"

  umount "$mnt/sys" "$mnt/proc" "$mnt/dev" "$mnt/boot" "$mnt"
  rmdir "$mnt"
  losetup -d "$loop"
  trap - EXIT
  info "BIOS GPT image $out  root=PARTUUID=$root_partuuid"
}

misl_img_pack() {
  local out mode=tree gzip=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --from-tree) mode=tree; shift ;;
      --from-disk|--raw-disk) mode=disk; shift ;;
      --gzip) gzip=1; shift ;;
      -o) out=${2:?}; shift 2 ;;
      -h|--help)
        printf '%s\n' "usage: misl img pack [--from-tree|--from-disk] [--gzip] [-o FILE]"
        return 0
        ;;
      *)
        if [[ -z ${out:-} && $1 != -* ]]; then
          out=$1
          shift
        else
          die "unknown option $1"
        fi
        ;;
    esac
  done
  misl_img_assert_host
  out=${out:-${MISL_IMG:-$(misl_img_default_out)}}
  [[ $out == /* ]] || out=$(pwd)/$out
  info "pack $LFS -> $out (mode=$mode)"
  trap 'die "img pack aborted (command failed)"' ERR
  if [[ -e $out && ${MISL_FORCE:-0} != 1 ]]; then
    die "refusing to overwrite $out (MISL_FORCE=1 or pick another path)"
  fi
  mkdir -p "$(dirname "$out")"

  if [[ $mode == disk ]]; then
    misl_img_from_disk "$out"
  else
    misl_img_from_tree "$out"
  fi

  if [[ $gzip == 1 ]]; then
    info "gzip $out"
    gzip -f -k "$out"
    info "compressed $out.gz"
  fi
  ls -lh "$out" ${out}.gz 2>/dev/null || ls -lh "$out"
  cat <<EOF

DigitalOcean Custom Images:
  raw .img (this file), optional gzip. BIOS + ext4 + cloud-init + sshd.
  Control panel → Backups & Snapshots → Custom Images → upload
  Create Droplet from the image and attach an SSH key.

EOF
}

# Host qemu only. Not a doctor/bootstrap dependency.
misl_img_test() {
  misl_img_assert_host
  command -v qemu-system-x86_64 >/dev/null 2>&1 || \
    die "qemu-system-x86_64 not on PATH. install it on the Fedora host (not via misl doctor)"
  local img= disk=virtio
  while [[ $# -gt 0 ]]; do
    case $1 in
      --ide) disk=ide; shift ;;
      --virtio) disk=virtio; shift ;;
      -i) img=${2:?}; shift 2 ;;
      -h|--help)
        printf '%s\n' "usage: misl img test [--virtio|--ide] [-i FILE.img]"
        return 0
        ;;
      *)
        if [[ -z ${img:-} && $1 != -* ]]; then
          img=$1
          shift
        else
          die "usage: misl img test [--virtio|--ide] [-i FILE.img]"
        fi
        ;;
    esac
  done
  img=${img:-${MISL_IMG:-$(misl_img_default_out)}}
  [[ $img == /* ]] || img=$(pwd)/$img
  [[ -f $img ]] || die "no image $img — ./misl img pack first"
  info "qemu $disk $img (Ctrl-a x to quit). virtio is what DigitalOcean uses."
  if [[ $disk == ide ]]; then
    qemu-system-x86_64 -machine q35 -m "${MISL_QEMU_MEM:-1024}" \
      -nographic -serial mon:stdio -no-reboot \
      -drive file="$img",format=raw,if=ide
  else
    qemu-system-x86_64 -machine q35 -m "${MISL_QEMU_MEM:-1024}" \
      -nographic -serial mon:stdio -no-reboot \
      -drive file="$img",format=raw,if=virtio
  fi
}

misl_img() {
  local sub=${1:-}
  shift || true
  case $sub in
    pack) misl_img_pack "$@" ;;
    test|qemu) misl_img_test "$@" ;;
    *) die "usage: misl img pack|test [--from-tree|--from-disk] [--gzip] [-o FILE]" ;;
  esac
}
