# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash

# Live ISO from a packed MISL .img. Host root, not chroot.
# Do not grub-mkrescue a copied rootfs — host GRUB + image modules
# mismatch (grub_memcpy / grub rescue). --installer is a stub.

misl_iso_default_out() {
  local img
  img=${MISL_IMG:-$(misl_img_default_out)}
  printf '%s\n' "${img%.img}.iso"
}

misl_iso_assert_host() {
  require_root
  [[ ${LFS:-} != / ]] || die "iso pack runs on the Fedora host. exit the chroot first"
}

misl_iso_usage_pack() {
  printf '%s\n' "usage: misl iso pack [--uefi|--bios] [--live|--installer] [-i FILE.img] [-o FILE.iso]"
}

misl_iso_usage_test() {
  printf '%s\n' "usage: misl iso test [--uefi|--bios] [--inspect] [-i FILE.iso]"
}

misl_iso_grub_mkrescue() {
  if command -v grub2-mkrescue >/dev/null 2>&1; then
    printf '%s\n' grub2-mkrescue
  elif command -v grub-mkrescue >/dev/null 2>&1; then
    printf '%s\n' grub-mkrescue
  else
    die "grub2-mkrescue not on PATH. dnf install grub2-tools-extra xorriso"
  fi
}

misl_iso_grub_dir() {
  local plat=$1 d
  for d in /usr/lib/grub /usr/lib/grub2; do
    if [[ -d $d/$plat ]]; then
      printf '%s/%s\n' "$d" "$plat"
      return 0
    fi
  done
  return 1
}

misl_iso_ovmf_code() {
  local c
  for c in \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.4m.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd
  do
    if [[ -f $c ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

misl_iso_ovmf_vars() {
  local c
  for c in \
    /usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS.4m.fd \
    /usr/share/OVMF/OVMF_VARS.fd
  do
    if [[ -f $c ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

# Copy guest path into initramfs dest, following one symlink hop.
misl_iso_install_file() {
  local root=$1 dest=$2 guest=$3
  local src=$root$guest tgt dir
  [[ -e $src || -L $src ]] || return 1
  mkdir -p "$dest$(dirname "$guest")"
  if [[ -L $src ]]; then
    [[ -e $dest$guest || -L $dest$guest ]] || cp -a "$src" "$dest$guest"
    tgt=$(readlink "$src")
    if [[ $tgt == /* ]]; then
      misl_iso_install_file "$root" "$dest" "$tgt" || true
    else
      dir=$(dirname "$guest")
      misl_iso_install_file "$root" "$dest" "$dir/$tgt" || true
    fi
  else
    [[ -e $dest$guest ]] && return 0
    cp -a "$src" "$dest$guest"
  fi
}

# Guest glibc ld.so has no --list. Walk NEEDED + interpreter with readelf.
misl_iso_find_so() {
  local root=$1 name=$2 d found
  if [[ $name == /* ]]; then
    [[ -e $root$name || -L $root$name ]] && { printf '%s\n' "$name"; return 0; }
    return 1
  fi
  for d in /lib64 /lib /usr/lib64 /usr/lib; do
    if [[ -e $root$d/$name || -L $root$d/$name ]]; then
      printf '%s/%s\n' "$d" "$name"
      return 0
    fi
  done
  found=$(find "$root/usr/lib" "$root/lib" "$root/lib64" "$root/usr/lib64" \
    -maxdepth 2 -name "$name" 2>/dev/null | head -1)
  if [[ -n ${found:-} ]]; then
    printf '%s\n' "${found#"$root"}"
    return 0
  fi
  return 1
}

misl_iso_needed() {
  readelf -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'
}

misl_iso_cp_libs_for() {
  local root=$1 dest=$2 elf=$3
  local interp soname guest seen=${4-}
  [[ -f $elf ]] || return 0
  interp=$(readelf -l "$elf" 2>/dev/null | sed -n 's/.*program interpreter: \([^]]*\).*/\1/p' | head -1)
  if [[ -n $interp ]]; then
    misl_iso_install_file "$root" "$dest" "$interp" || true
  fi
  while read -r soname; do
    [[ -n $soname ]] || continue
    guest=$(misl_iso_find_so "$root" "$soname") || continue
    case " $seen " in
      *" $guest "*) continue ;;
    esac
    seen+=" $guest"
    misl_iso_install_file "$root" "$dest" "$guest" || true
    misl_iso_cp_libs_for "$root" "$dest" "$(readlink -f "$root$guest")" "$seen"
  done < <(misl_iso_needed "$elf")
}

misl_iso_mkinitramfs() {
  local root=$1 dest=$2 kver=$3
  local ird path real bins modver guest so
  ird=$(mktemp -d /var/tmp/misl-iso-initrd.XXXXXX)
  mkdir -p "$ird"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,tmp,media/iso,media/squash,media/upper,newroot,lib/modules}

  bins=(
    /usr/bin/bash /bin/bash /bin/sh
    /usr/bin/mount /bin/mount
    /usr/bin/umount /bin/umount
    /usr/sbin/switch_root /sbin/switch_root
    /usr/bin/mkdir /bin/mkdir
    /usr/bin/sleep /bin/sleep
    /usr/sbin/modprobe /sbin/modprobe
    /usr/bin/kmod /bin/kmod
    /usr/sbin/blkid /sbin/blkid
    /usr/bin/ln /bin/ln
  )
  for path in "${bins[@]}"; do
    if [[ -e $root$path || -L $root$path ]]; then
      misl_iso_install_file "$root" "$ird" "$path" || true
      real=$(readlink -f "$root$path" 2>/dev/null || true)
      if [[ -n $real && -f $real ]]; then
        misl_iso_cp_libs_for "$root" "$ird" "$real"
      fi
    fi
  done
  mkdir -p "$ird/bin"
  if [[ -x $ird/usr/bin/bash && ! -e $ird/bin/bash ]]; then
    ln -sfn /usr/bin/bash "$ird/bin/bash"
  fi
  if [[ -e $ird/bin/bash && ! -e $ird/bin/sh ]]; then
    ln -sfn bash "$ird/bin/sh"
  elif [[ -e $ird/usr/bin/bash && ! -e $ird/bin/sh ]]; then
    ln -sfn /usr/bin/bash "$ird/bin/sh"
  fi
  [[ -x $ird/bin/bash || -x $ird/usr/bin/bash || -x $ird/bin/sh ]] || \
    die "no shell in the image — cannot build live initramfs"
  # LFS is merged-usr: /lib and /lib64 are symlinks to usr/lib. Copying
  # the interpreter as /lib64/ld-linux-*.so.2 turns lib64 into a directory
  # with only the loader — libc stays in /usr/lib and PID 1 exits 127.
  local link tgt
  for link in /lib /lib64 /usr/lib64; do
    if [[ -L $root$link ]]; then
      tgt=$(readlink "$root$link")
      rm -rf "$ird$link"
      mkdir -p "$ird$(dirname "$link")"
      ln -sfn "$tgt" "$ird$link"
    fi
  done
  # The NEEDED walk has been missing libc/readline on this tree. Copy
  # by name from the guest and refuse to pack without libc.so.6.
  local so
  for so in libc.so.6 libreadline.so.8 libhistory.so.8 libncursesw.so.6 \
            libncurses.so.6 libtinfo.so.6 libdl.so.2 libpthread.so.0 \
            libmount.so.1 libblkid.so.1 libuuid.so.1 libsystemd.so.0 \
            libcap.so.2 libcrypt.so.2; do
    guest=$(misl_iso_find_so "$root" "$so") || continue
    misl_iso_install_file "$root" "$ird" "$guest" || true
  done
  if [[ ! -e $ird/usr/lib/libc.so.6 && ! -e $ird/lib/libc.so.6 && ! -e $ird/lib64/libc.so.6 ]]; then
    die "initramfs has no libc.so.6 (have: $(ls "$ird/usr/lib" 2>/dev/null | tr '\n' ' ')). guest usr/lib=$(ls "$root/usr/lib"/libc.so* 2>/dev/null | tr '\n' ' ')"
  fi

  modver=$kver
  if [[ ! -d $root/lib/modules/$modver && -d $root/lib/modules/${kver%-misl} ]]; then
    modver=${kver%-misl}
  fi
  if [[ -d $root/lib/modules/$modver ]]; then
    mkdir -p "$ird/lib/modules"
    cp -a "$root/lib/modules/$modver" "$ird/lib/modules/"
    if [[ $modver != "$kver" ]]; then
      ln -sfn "$modver" "$ird/lib/modules/$kver"
    fi
  fi
  # =y is built-in (no squashfs.ko). =m is a module. Either is fine.
  if ! grep -qE '^CONFIG_SQUASHFS=[ym]' "$root/boot/config-$kver" 2>/dev/null \
     && ! grep -qE '^CONFIG_SQUASHFS=[ym]' "$root/boot/config-$modver" 2>/dev/null \
     && ! grep -qE '^CONFIG_SQUASHFS=[ym]' "$root/boot"/config-* 2>/dev/null \
     && ! find "$root/lib/modules" "$ird/lib/modules" -name 'squashfs.ko*' 2>/dev/null | grep -q .; then
    die "no squashfs for $kver (need CONFIG_SQUASHFS=y or squashfs.ko). boot=$(ls "$root/boot"/config-* 2>/dev/null | tr '\n' ' ') modules=$(ls "$root/lib/modules" 2>/dev/null | tr '\n' ' '). grep CONFIG_SQUASHFS /mnt/misl/boot/config-* then rebuild 10-boot/linux + img pack"
  fi

  mknod -m 600 "$ird/dev/console" c 5 1 2>/dev/null || true
  mknod -m 666 "$ird/dev/null" c 1 3 2>/dev/null || true

  cat >"$ird/init" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
printf 'misl live: init\n'

fail() {
  printf 'misl live: %s\n' "$*"
  printf 'misl live: init hanging (no shell)\n'
  while :; do sleep 60 2>/dev/null || true; done
}

modprobe iso9660 2>/dev/null
modprobe isofs 2>/dev/null
modprobe squashfs 2>/dev/null
modprobe overlay 2>/dev/null
modprobe loop 2>/dev/null
modprobe cdrom 2>/dev/null
modprobe sr_mod 2>/dev/null
modprobe ahci 2>/dev/null
modprobe sd_mod 2>/dev/null

for ((i = 0; i < 40; i++)); do
  [ -b /dev/sr0 ] || [ -b /dev/cdrom ] && break
  sleep 0.25 2>/dev/null || true
done

found=
for dev in /dev/sr0 /dev/sr1 /dev/cdrom /dev/vda /dev/vdb /dev/sda /dev/sdb; do
  [ -b "$dev" ] || continue
  mount -o ro "$dev" /media/iso 2>/dev/null || continue
  if [ -f /media/iso/LiveOS/squashfs.img ]; then
    found=$dev
    break
  fi
  umount /media/iso 2>/dev/null || true
done
[ -n "$found" ] || fail "no LiveOS/squashfs.img on optical/virtio disk"

mount -t squashfs -o ro /media/iso/LiveOS/squashfs.img /media/squash \
  || fail "mount squashfs failed"

mkdir -p /media/upper/upper /media/upper/work
if mount -t tmpfs tmpfs /media/upper \
  && mkdir -p /media/upper/upper /media/upper/work \
  && mount -t overlay overlay \
    -o lowerdir=/media/squash,upperdir=/media/upper/upper,workdir=/media/upper/work \
    /newroot; then
  :
else
  printf 'misl live: overlay unavailable, read-only squashfs root\n'
  mount --bind /media/squash /newroot || fail "bind squashfs to /newroot failed"
fi

mkdir -p /newroot/run/live/iso /newroot/run/live/squash /newroot/run/live/upper
mount --move /media/iso /newroot/run/live/iso 2>/dev/null || true
mount --move /media/squash /newroot/run/live/squash 2>/dev/null || true
mount --move /media/upper /newroot/run/live/upper 2>/dev/null || true

[ -x /newroot/sbin/init ] || [ -x /newroot/usr/sbin/init ] \
  || fail "no /sbin/init in live root"
if [ -x /newroot/sbin/init ]; then
  exec switch_root /newroot /sbin/init
else
  exec switch_root /newroot /usr/sbin/init
fi
EOF
  chmod 0755 "$ird/init"

  mkdir -p "$(dirname "$dest")"
  ( cd "$ird" && find . | cpio -o -H newc --owner=0:0 ) | gzip -9 >"$dest"
  rm -rf "$ird"
  [[ -s $dest ]] || die "initramfs write failed: $dest"
}

misl_iso_from_img() {
  local img=$1 out=$2 fw=$3
  local work loop rootmnt stage isow kver gmr platdir p2 p3 label
  require_cmd losetup mount umount rsync mksquashfs cpio gzip blkid readelf find
  gmr=$(misl_iso_grub_mkrescue)
  case $fw in
    bios)
      platdir=$(misl_iso_grub_dir i386-pc) \
        || die "no GRUB i386-pc modules. dnf install grub2-pc-modules"
      ;;
    uefi)
      platdir=$(misl_iso_grub_dir x86_64-efi) \
        || die "no GRUB x86_64-efi modules. dnf install grub2-efi-x64-modules mtools"
      require_cmd mformat mcopy || \
        die "mtools required for UEFI ISO. dnf install mtools"
      ;;
    *) die "internal: firmware $fw" ;;
  esac

  work=$(mktemp -d /var/tmp/misl-iso.XXXXXX)
  rootmnt=$work/mnt
  stage=$work/stage
  isow=$work/iso
  mkdir -p "$rootmnt" "$stage" "$isow/boot/grub" "$isow/LiveOS"

  loop=$(losetup --find --show --partscan "$img")
  [[ -n $loop ]] || die "losetup failed for $img"
  # shellcheck disable=SC2064
  trap 'umount -R '"$rootmnt"'/boot 2>/dev/null || true; umount -R '"$rootmnt"' 2>/dev/null || true; losetup -d '"$loop"' 2>/dev/null || true; rm -rf '"$work" EXIT

  udevadm settle 2>/dev/null || sleep 1
  p2= p3=
  for p in "$loop"p*; do
    [[ -b $p ]] || continue
    label=$(blkid -p -s LABEL -o value "$p" 2>/dev/null || true)
    case $label in
      mislboot) p2=$p ;;
      misl) p3=$p ;;
    esac
  done
  p2=${p2:-${loop}p2}
  p3=${p3:-${loop}p3}
  [[ -b $p2 && -b $p3 ]] || die "loop partitions missing under $loop (need labels mislboot/misl or p2/p3)"

  mount -o ro "$p3" "$rootmnt"
  mkdir -pv "$rootmnt/boot"
  mount -o ro "$p2" "$rootmnt/boot"

  shopt -s nullglob
  local vz
  vz=("$rootmnt"/boot/vmlinuz-*)
  shopt -u nullglob
  (( ${#vz[@]} > 0 )) || die "no vmlinuz-* on image boot partition"
  kver=${vz[0]##*/vmlinuz-}
  info "kernel $kver from $img"

  info "rsync image -> squashfs staging"
  # -X would copy guest xattrs; Fedora denies fremovexattr(security.selinux)
  # on /var/tmp even as root. Drop MAC xattrs, keep ACLs + the rest of -aHA.
  rsync -aHA --numeric-ids --xattrs \
    --filter='-x security.selinux' \
    --filter='-x security.ima' \
    --exclude '/proc/**' --exclude '/sys/**' --exclude '/dev/**' \
    --exclude '/run/**' --exclude '/tmp/**' --exclude '/boot/efi/**' \
    --exclude '/tools/**' --exclude '/usr/src/**' \
    --exclude '/var/tmp/**' --exclude '/var/lib/misl/logs/**' \
    "$rootmnt"/ "$stage"/ || die "rsync failed"

  mkdir -pv "$stage"/{proc,sys,dev,run,tmp,run/live/iso,run/live/squash,run/live/upper}
  chmod 1777 "$stage/tmp"
  {
    printf '%s\n' '# /etc/fstab — MIS Linux live ISO'
    printf 'proc  /proc  proc  nosuid,noexec,nodev  0 0\n'
    printf 'sysfs /sys   sysfs nosuid,noexec,nodev  0 0\n'
    printf 'devtmpfs /dev devtmpfs mode=0755,nosuid 0 0\n'
    printf 'tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0\n'
  } >"$stage/etc/fstab"

  umount "$rootmnt/boot" "$rootmnt"
  losetup -d "$loop"
  loop=
  trap 'rm -rf '"$work" EXIT

  info "initramfs $kver"
  misl_iso_mkinitramfs "$stage" "$isow/boot/initramfs-$kver.img" "$kver"
  cp -a "$stage/boot/vmlinuz-$kver" "$isow/boot/"

  info "mksquashfs (this is the live root)"
  mksquashfs "$stage" "$isow/LiveOS/squashfs.img" -noappend -comp gzip -e boot/grub/grub.cfg
  rm -rf "$stage"

  {
    printf '%s\n' 'set default=0' 'set timeout=8'
    printf '%s\n' 'insmod all_video' 'insmod gfxterm' 'insmod font'
    printf '%s\n' 'if loadfont unicode ; then terminal_output gfxterm ; fi'
    printf '%s\n' 'serial --unit=0 --speed=115200'
    printf '%s\n' 'terminal_input console serial'
    printf '%s\n' 'insmod iso9660' 'insmod fat' 'insmod part_gpt'
    printf '%s\n' 'search --no-floppy --file --set=root /LiveOS/squashfs.img'
    printf 'menuentry "%s Live" {\n' "${MISL_PRETTY_NAME:-MIS Linux ${MISL_VERSION:-0.3}}"
    printf '        linux /boot/vmlinuz-%s console=tty0 console=ttyS0,115200n8\n' "$kver"
    printf '        initrd /boot/initramfs-%s.img\n' "$kver"
    printf '}\n'
    printf 'menuentry "%s Live (nomodeset)" {\n' "${MISL_PRETTY_NAME:-MIS Linux ${MISL_VERSION:-0.3}}"
    printf '        linux /boot/vmlinuz-%s nomodeset console=tty0 console=ttyS0,115200n8\n' "$kver"
    printf '        initrd /boot/initramfs-%s.img\n' "$kver"
    printf '}\n'
  } >"$isow/boot/grub/grub.cfg"

  info "$gmr $fw ($platdir) -> $out"
  mkdir -p "$(dirname "$out")"
  rm -f "$out"
  if [[ $fw == uefi ]]; then
    "$gmr" --directory="$platdir" -o "$out" "$isow" \
      -isohybrid-gpt-basdat \
      || die "$gmr failed"
  else
    "$gmr" --directory="$platdir" -o "$out" "$isow" \
      || die "$gmr failed"
  fi
  rm -rf "$work"
  trap - EXIT
  info "live ISO $out ($fw)"
}

misl_iso_pack() {
  local img= out= fw=uefi kind=live saw_fw=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --uefi)
        [[ $saw_fw == 1 && $fw != uefi ]] && die "pass only one of --uefi or --bios"
        fw=uefi; saw_fw=1; shift ;;
      --bios)
        [[ $saw_fw == 1 && $fw != bios ]] && die "pass only one of --uefi or --bios"
        fw=bios; saw_fw=1; shift ;;
      --boot|--usb)
        # UEFI pack already writes a GPT hybrid. Kept so the flag is valid.
        shift ;;
      --live) kind=live; shift ;;
      --installer) kind=installer; shift ;;
      -i) img=${2:?}; shift 2 ;;
      -o) out=${2:?}; shift 2 ;;
      --output|--image)
        die "$(misl_iso_usage_pack)"
        ;;
      -h|--help)
        misl_iso_usage_pack
        return 0
        ;;
      -*)
        die "unknown option $1 ($(misl_iso_usage_pack))"
        ;;
      *)
        if [[ -z ${img:-} ]]; then
          img=$1
        elif [[ -z ${out:-} ]]; then
          out=$1
        else
          die "$(misl_iso_usage_pack)"
        fi
        shift
        ;;
    esac
  done

  if [[ $kind == installer ]]; then
    die "installer ISO is a stub (not implemented). use: misl iso pack --live"
  fi

  misl_iso_assert_host
  img=${img:-${MISL_IMG:-$(misl_img_default_out)}}
  [[ $img == /* ]] || img=$(pwd)/$img
  out=${out:-${MISL_ISO:-${img%.img}.iso}}
  [[ $out == /* ]] || out=$(pwd)/$out
  [[ -f $img ]] || die "no image $img — ./misl img pack first"
  if [[ -e $out && ${MISL_FORCE:-0} != 1 ]]; then
    die "refusing to overwrite $out (MISL_FORCE=1 or pick another path)"
  fi
  info "live ISO $img -> $out (firmware=$fw)"
  trap 'die "iso pack aborted (command failed)"' ERR
  misl_iso_from_img "$img" "$out" "$fw"
  ls -lh "$out"
}

misl_iso_inspect() {
  misl_iso_assert_host
  require_cmd mount umount zcat cpio readelf find ls
  local iso=${1:?} mnt ird img
  [[ $iso == /* ]] || iso=$(pwd)/$iso
  [[ -f $iso ]] || die "no ISO $iso — ./misl iso pack first"
  mnt=$(mktemp -d /var/tmp/misl-iso-mnt.XXXXXX)
  ird=$(mktemp -d /var/tmp/misl-iso-ird.XXXXXX)
  # Expand paths now. A RETURN trap that names $mnt leaks to the caller
  # and trips set -u (mnt: unbound) on iso test --inspect's return.
  # shellcheck disable=SC2064
  trap "umount '$mnt' 2>/dev/null || true; rm -rf '$mnt' '$ird'; trap - RETURN EXIT" RETURN EXIT
  mount -o loop,ro "$iso" "$mnt" || die "mount $iso failed"
  shopt -s nullglob
  local imgs=( "$mnt"/boot/initramfs-*.img "$mnt"/boot/initrd* )
  shopt -u nullglob
  (( ${#imgs[@]} > 0 )) || die "no initramfs under $iso /boot"
  img=${imgs[0]}
  info "inspect $iso"
  info "initramfs ${img#"$mnt"}"
  zcat "$img" 2>/dev/null | ( cd "$ird" && cpio -id --quiet ) \
    || gzip -dc "$img" | ( cd "$ird" && cpio -id --quiet ) \
    || die "cpio extract failed"
  printf '\n== /init ==\n'
  ls -l "$ird/init" 2>/dev/null || printf '(missing /init)\n'
  head -8 "$ird/init" 2>/dev/null || true
  printf '\n== bin /lib /lib64 /usr/lib ==\n'
  ls -l "$ird/bin" "$ird/lib" "$ird/lib64" "$ird/usr/lib" 2>/dev/null || true
  printf '\n== interpreter + NEEDED (bash/sh/mount) ==\n'
  local f
  for f in "$ird/bin/sh" "$ird/bin/bash" "$ird/usr/bin/bash" "$ird/bin/mount"; do
    [[ -e $f || -L $f ]] || continue
    printf '%s\n' "$f"
    readelf -l "$f" 2>/dev/null | grep -F interpreter || true
    readelf -d "$f" 2>/dev/null | grep NEEDED || true
  done
  printf '\n== ld-linux / libc / readline / ncurses / tinfo ==\n'
  find "$ird" \( \
      -name 'ld-linux*' -o -name 'libc.so*' -o -name 'libreadline*' \
      -o -name 'libhistory*' -o -name 'libncurses*' -o -name 'libtinfo*' \
    \) -ls 2>/dev/null || true
  printf '\n== squashfs on ISO ==\n'
  ls -l "$mnt/LiveOS/squashfs.img" 2>/dev/null || printf '(no LiveOS/squashfs.img)\n'
  umount "$mnt" 2>/dev/null || true
  rm -rf "$mnt" "$ird"
  trap - RETURN EXIT
}

misl_iso_test() {
  misl_iso_assert_host
  local iso= fw=uefi saw_fw=0 inspect=0 code vars varstmp
  while [[ $# -gt 0 ]]; do
    case $1 in
      --inspect)
        inspect=1; shift ;;
      --uefi)
        [[ $saw_fw == 1 && $fw != uefi ]] && die "pass only one of --uefi or --bios"
        fw=uefi; saw_fw=1; shift ;;
      --bios)
        [[ $saw_fw == 1 && $fw != bios ]] && die "pass only one of --uefi or --bios"
        fw=bios; saw_fw=1; shift ;;
      -i) iso=${2:?}; shift 2 ;;
      --output|--image|-o)
        die "$(misl_iso_usage_test)"
        ;;
      -h|--help)
        misl_iso_usage_test
        return 0
        ;;
      -*)
        die "unknown option $1 ($(misl_iso_usage_test))"
        ;;
      *)
        if [[ -z ${iso:-} ]]; then
          iso=$1
          shift
        else
          die "$(misl_iso_usage_test)"
        fi
        ;;
    esac
  done
  iso=${iso:-${MISL_ISO:-$(misl_iso_default_out)}}
  [[ $iso == /* ]] || iso=$(pwd)/$iso
  [[ -f $iso ]] || die "no ISO $iso — ./misl iso pack first"
  if [[ $inspect == 1 ]]; then
    misl_iso_inspect "$iso"
    return 0
  fi
  command -v qemu-system-x86_64 >/dev/null 2>&1 || \
    die "qemu-system-x86_64 not on PATH. install it on the Fedora host (not via misl doctor)"
  info "qemu $fw cdrom $iso (Ctrl-a x to quit)"
  if [[ $fw == bios ]]; then
    qemu-system-x86_64 -machine q35 -m "${MISL_QEMU_MEM:-2048}" \
      -nographic -serial mon:stdio -no-reboot \
      -boot d -cdrom "$iso"
  else
    code=$(misl_iso_ovmf_code) \
      || die "OVMF firmware not found. dnf install edk2-ovmf"
    vars=$(misl_iso_ovmf_vars) || vars=
    varstmp=
    if [[ -n $vars ]]; then
      varstmp=$(mktemp /var/tmp/misl-ovmf-vars.XXXXXX)
      cp -a "$vars" "$varstmp"
      qemu-system-x86_64 -machine q35 -m "${MISL_QEMU_MEM:-2048}" \
        -nographic -serial mon:stdio -no-reboot \
        -drive if=pflash,format=raw,readonly=on,file="$code" \
        -drive if=pflash,format=raw,file="$varstmp" \
        -boot d -cdrom "$iso"
      rm -f "$varstmp"
    else
      qemu-system-x86_64 -machine q35 -m "${MISL_QEMU_MEM:-2048}" \
        -nographic -serial mon:stdio -no-reboot \
        -drive if=pflash,format=raw,readonly=on,file="$code" \
        -boot d -cdrom "$iso"
    fi
  fi
}

misl_iso_usb_usage() {
  cat <<'EOF'
usage: misl iso usb --list
       MISL_FORCE=1 misl iso usb FILE.iso /dev/disk/by-id/usb-…

Pick the disk node from --list (no -partN). Example:

  ./misl iso usb --list
  MISL_FORCE=1 ./misl iso usb /var/tmp/misl-0.3-terminal-uefi.iso \
    /dev/disk/by-id/usb-SanDisk_Cruzer_Blade_00016316113023151659-0:0

Wipes the stick. GPT + one FAT32 ESP (MISLUSB). Needs a --uefi ISO.
EOF
}

# Disk nodes only. Skip -part* and optical (DVD adapters).
misl_iso_usb_list() {
  local p typ size model
  shopt -s nullglob
  local nodes=( /dev/disk/by-id/usb-* )
  shopt -u nullglob
  (( ${#nodes[@]} > 0 )) || { printf 'no /dev/disk/by-id/usb-* devices\n'; return 0; }
  for p in "${nodes[@]}"; do
    [[ $p == *-part* ]] && continue
    [[ -b $p ]] || continue
    typ=$(lsblk -dn -o TYPE "$p" 2>/dev/null || true)
    [[ $typ == rom ]] && continue
    size=$(lsblk -dn -o SIZE "$p" 2>/dev/null || true)
    model=$(lsblk -dn -o MODEL "$p" 2>/dev/null | tr -s ' ' || true)
    printf '%s' "$p"
    [[ -n $size ]] && printf '  %s' "$size"
    [[ -n $model ]] && printf '  %s' "$model"
    printf '\n'
  done
}

# Write a live ISO onto a USB stick as GPT + FAT ESP.
# dd of a mkrescue ISO is a CD image; many boxes never list that as USB-HDD.
misl_iso_usb() {
  local iso= dev= part mnt isomnt host host_real disk_real
  while [[ $# -gt 0 ]]; do
    case $1 in
      --list)
        misl_iso_usb_list
        return 0
        ;;
      -i) iso=${2:?}; shift 2 ;;
      -o|--device)
        die "$(misl_iso_usb_usage)"
        ;;
      -h|--help)
        misl_iso_usb_usage
        return 0
        ;;
      -*)
        die "$(misl_iso_usb_usage)"
        ;;
      *)
        if [[ -z ${iso:-} ]]; then
          iso=$1
        elif [[ -z ${dev:-} ]]; then
          dev=$1
        else
          die "$(misl_iso_usb_usage)"
        fi
        shift
        ;;
    esac
  done
  [[ -n ${iso:-} && -n ${dev:-} ]] || \
    die "$(misl_iso_usb_usage)"
  misl_iso_assert_host
  require_cmd parted mkfs.vfat mount umount rsync lsblk wipefs
  [[ $iso == /* ]] || iso=$(pwd)/$iso
  [[ -f $iso ]] || die "no ISO $iso"
  [[ $dev == /dev/disk/by-id/usb-* ]] || \
    die "pass a /dev/disk/by-id/usb-* disk node (not a partition, not /dev/sdX)"
  [[ $dev != *-part* ]] || die "use the disk node, not $dev"
  [[ -b $dev ]] || die "not a block device: $dev"
  host=$(misl_host_disk)
  host_real=$(misl_disk_realpath "$host")
  disk_real=$(misl_disk_realpath "$dev")
  if [[ -n $host_real && -n $disk_real && $host_real == "$disk_real" ]]; then
    die "refusing to write the host root disk ($dev)"
  fi
  if [[ ${MISL_FORCE:-0} != 1 ]]; then
    die "this wipes $dev ($disk_real). MISL_FORCE=1 ./misl iso usb $iso $dev"
  fi
  info "usb $iso -> $dev ($disk_real)"
  umount "$dev"* 2>/dev/null || true
  umount "$dev"-part* 2>/dev/null || true
  wipefs -a "$dev"
  parted -s "$dev" mklabel gpt
  parted -s "$dev" mkpart ESP fat32 1MiB 100%
  parted -s "$dev" set 1 esp on
  udevadm settle 2>/dev/null || sleep 1
  part=$(misl_disk_part "$dev" 1)
  [[ -b $part ]] || die "no partition $part after parted"
  mkfs.vfat -F 32 -n MISLUSB "$part"
  mnt=$(mktemp -d /var/tmp/misl-usb.XXXXXX)
  isomnt=$(mktemp -d /var/tmp/misl-usb-iso.XXXXXX)
  # shellcheck disable=SC2064
  trap "umount '$mnt' 2>/dev/null || true; umount '$isomnt' 2>/dev/null || true; rm -rf '$mnt' '$isomnt'; trap - RETURN EXIT" RETURN EXIT
  mount "$part" "$mnt"
  mount -o loop,ro "$iso" "$isomnt"
  rsync -a --no-links "$isomnt"/ "$mnt"/ || die "rsync ISO -> USB failed"
  if [[ ! -f $mnt/EFI/BOOT/BOOTX64.EFI && ! -f $mnt/efi/boot/bootx64.efi ]]; then
    die "ISO has no EFI/BOOT/BOOTX64.EFI — pack with --uefi"
  fi
  umount "$mnt" "$isomnt"
  rm -rf "$mnt" "$isomnt"
  trap - RETURN EXIT
  info "USB $dev ready (UEFI: look for MISLUSB / EFI USB, Secure Boot off)"
}

misl_iso() {
  local sub=${1:-}
  shift || true
  case $sub in
    pack) misl_iso_pack "$@" ;;
    test|qemu) misl_iso_test "$@" ;;
    inspect) misl_iso_test --inspect "$@" ;;
    usb) misl_iso_usb "$@" ;;
    *) die "usage: misl iso pack|test|inspect|usb [--uefi|--bios] [--inspect] [-i FILE] [-o FILE]" ;;
  esac
}
