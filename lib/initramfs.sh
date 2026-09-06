# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Initramfs for the installed system (plan-0.4 item 4). No dracut.
#
#   <root>/boot/microcode.img          early cpio, uncompressed (AMD/Intel)
#   <root>/boot/initramfs-<kver>.img   gzip newc: /init, modules, firmware
#   <root>/var/lib/misl/initramfs/<kver>.files    what build wrote (remove)
#   <root>/var/lib/misl/initramfs/<kver>.modules  name<TAB>path|builtin|missing
#
# GRUB loads microcode.img first, then the initramfs; the kernel sees one
# buffer with the uncompressed early cpio prepended. The userland copy
# (shell, libs, merged-usr links) is shared with `iso pack`. The /init
# here is separate and small: root= by UUID/PARTUUID/LABEL, optional
# fsck, switch_root to systemd, rescue shell on failure.
#
# cpio is not in the target (or every host). newc is written by python3,
# which both have. MISL_INITRAMFS=0 turns all of this off.

MISL_INITRAMFS_KVER=7.1.8-misl
MISL_INITRAMFS_FW_STAGE=/usr/share/misl/linux-firmware
# Modules wanted when they are =m. Built-in or absent ones are skipped.
# NVMe, AHCI, ext4 are also forced =y in 10-boot/linux (fallback).
MISL_INITRAMFS_BASE_MODULES="nvme ahci sd_mod sr_mod usb_storage uas xhci_pci xhci_hcd ehci_pci ohci_pci virtio_pci virtio_blk virtio_scsi ext4 vfat nls_cp437 nls_iso8859_1 crc32c_generic crc32c_intel"

misl_initramfs_enabled() { [[ ${MISL_INITRAMFS:-1} != 0 ]]; }

misl_initramfs_state() { printf '%s/var/lib/misl/initramfs\n' "${1%/}"; }

misl_initramfs_modname() {
  local n=${1##*/}
  n=${n%.xz}; n=${n%.zst}; n=${n%.gz}; n=${n%.ko}
  printf '%s\n' "${n//-/_}"
}

# /lib/modules dir name for kver (7.1.8-misl or 7.1.8, like iso pack).
misl_initramfs_modver() {
  local root=$1 kver=$2
  if [[ ! -d $root/lib/modules/$kver && -d $root/lib/modules/${kver%-misl} ]]; then
    printf '%s\n' "${kver%-misl}"
  else
    printf '%s\n' "$kver"
  fi
}

# One module name per line, `#` comments. File and line on a bad name.
misl_initramfs_list_parse() {
  local f=$1 line n=0 tok
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%%#*}
    for tok in $line; do
      [[ $tok =~ ^[A-Za-z0-9_-]+$ ]] || die "$f:$n: bad module name '$tok'"
      printf '%s\n' "${tok//-/_}"
    done
  done <"$f"
}

# Base list, then initramfs.list of every applied overlay (nested too),
# then MISL_INITRAMFS_MODULES. Unique, order kept.
misl_initramfs_requests() {
  local q f m seen=" " all
  all=$MISL_INITRAMFS_BASE_MODULES
  if declare -F misl_overlay_all >/dev/null 2>&1; then
    while IFS= read -r q; do
      [[ -n $q ]] || continue
      f=$(misl_overlay_home)/$q/initramfs.list
      [[ -f $f ]] || continue
      misl_overlay_applied "$q" || continue
      all+=" $(misl_initramfs_list_parse "$f" | tr '\n' ' ')" || exit 1
    done <<<"$(misl_overlay_all)"
  fi
  all+=" ${MISL_INITRAMFS_MODULES:-}"
  for m in $all; do
    m=${m//-/_}
    [[ $seen == *" $m "* ]] && continue
    seen+="$m "
    printf '%s\n' "$m"
  done
}

# Print "name<TAB>relpath" deps-first for every request that is a
# module, "name<TAB>builtin" or "name<TAB>missing" otherwise.
misl_initramfs_resolve() {
  local moddir=$1; shift
  local -A path_of=() deps_of=() done_=() builtin=()
  local line p d n
  [[ -f $moddir/modules.dep ]] || die "no $moddir/modules.dep (run depmod, or rebuild 10-boot/linux)"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    p=${line%%:*}
    n=$(misl_initramfs_modname "$p")
    path_of[$n]=$p
    deps_of[$p]=${line#*:}
  done <"$moddir/modules.dep"
  if [[ -f $moddir/modules.builtin ]]; then
    while IFS= read -r p; do
      [[ -n $p ]] && builtin[$(misl_initramfs_modname "$p")]=1
    done <"$moddir/modules.builtin"
  fi
  _misl_ird_visit() {
    local rp=$1 dp
    [[ -n ${done_[$rp]:-} ]] && return 0
    done_[$rp]=1
    for dp in ${deps_of[$rp]:-}; do
      _misl_ird_visit "$dp"
    done
    printf '%s\t%s\n' "$(misl_initramfs_modname "$rp")" "$rp"
  }
  for n in "$@"; do
    if [[ -n ${path_of[$n]:-} ]]; then
      _misl_ird_visit "${path_of[$n]}"
    elif [[ -n ${builtin[$n]:-} ]]; then
      printf '%s\tbuiltin\n' "$n"
    else
      printf '%s\tmissing\n' "$n"
    fi
  done
}

# firmware= tags from a .ko (plain, .xz, .gz, .zst if the tool exists).
misl_initramfs_ko_firmware() {
  local ko=$1
  case $ko in
    *.xz)  command -v xz >/dev/null 2>&1 || { warn "no xz: firmware of $ko unknown"; return 0; }
           xz -dc "$ko" ;;
    *.gz)  gzip -dc "$ko" ;;
    *.zst) command -v zstd >/dev/null 2>&1 || { warn "no zstd: firmware of $ko unknown"; return 0; }
           zstd -dc "$ko" ;;
    *)     cat "$ko" ;;
  esac | tr '\0' '\n' | sed -n 's/^firmware=//p' || true
}

# Early microcode cpio tree. Prints nothing and returns 1 if no blobs.
misl_initramfs_ucode_tree() {
  local root=$1 out=$2 stage f got=1 d
  stage=$root$MISL_INITRAMFS_FW_STAGE
  d=$out/kernel/x86/microcode
  shopt -s nullglob
  local amd=( "$stage"/amd-ucode/microcode_amd*.bin )
  local intel=( "$root"/usr/share/misl/intel-ucode/* "$stage"/intel-ucode/* )
  shopt -u nullglob
  if (( ${#amd[@]} )); then
    mkdir -p "$d"
    for f in "${amd[@]}"; do cat "$f"; done >"$d/AuthenticAMD.bin"
    got=0
  fi
  if (( ${#intel[@]} )); then
    mkdir -p "$d"
    for f in "${intel[@]}"; do [[ -f $f ]] && cat "$f"; done >"$d/GenuineIntel.bin"
    got=0
  fi
  return "$got"
}

# newc writer: python3 so neither host nor target needs cpio.
# Extra char nodes (dev/console, dev/null) are added without mknod/root.
misl_initramfs_cpio() {
  local dir=$1 nodes=${2:-}
  python3 - "$dir" "$nodes" <<'PY'
import os, stat, sys
top, nodes = sys.argv[1], sys.argv[2]
out = sys.stdout.buffer
ino = [1000]
def hdr(name, mode, size, nlink=1, rmaj=0, rmin=0):
    ino[0] += 1
    n = name.encode() + b"\0"
    h = "070701" + "".join("%08X" % v for v in (
        ino[0], mode, 0, 0, nlink, 0, size, 0, 0, rmaj, rmin, len(n), 0))
    b = h.encode() + n
    out.write(b + b"\0" * ((4 - len(b) % 4) % 4))
def data(b):
    out.write(b + b"\0" * ((4 - len(b) % 4) % 4))
names = []
for d, dirs, files in os.walk(top):
    dirs.sort()
    rel = os.path.relpath(d, top)
    if rel != ".":
        names.append(rel)
    for f in sorted(files):
        names.append(os.path.normpath(os.path.join(rel, f)))
    for x in dirs:
        if os.path.islink(os.path.join(d, x)):
            names.append(os.path.normpath(os.path.join(rel, x)))
seen = set()
for name in names:
    if name in seen:
        continue
    seen.add(name)
    p = os.path.join(top, name)
    st = os.lstat(p)
    if stat.S_ISLNK(st.st_mode):
        t = os.readlink(p).encode()
        hdr(name, st.st_mode, len(t)); data(t)
    elif stat.S_ISDIR(st.st_mode):
        hdr(name, st.st_mode, 0, 2)
    elif stat.S_ISREG(st.st_mode):
        with open(p, "rb") as fh:
            b = fh.read()
        hdr(name, st.st_mode, len(b)); data(b)
for spec in nodes.split():
    name, maj, mn, perm = spec.split(":")
    if name in seen:
        continue
    hdr(name, stat.S_IFCHR | int(perm, 8), 0, 1, int(maj), int(mn))
hdr("TRAILER!!!", 0, 0)
PY
}

# List one or more newc archives in a file (plain or gzip, concatenated).
misl_initramfs_cpio_list() {
  python3 - "$1" <<'PY'
import gzip, sys
raw = open(sys.argv[1], "rb").read()
def walk(b, tag):
    i = 0
    while i + 110 <= len(b):
        if b[i:i+6] != b"070701":
            if b[i:i+2] == b"\x1f\x8b":
                walk(gzip.decompress(b[i:]), "gz"); return
            i += 1; continue
        f = [int(b[i+6+8*k:i+14+8*k], 16) for k in range(13)]
        mode, size, nlen = f[1], f[6], f[11]
        name = b[i+110:i+110+nlen-1].decode()
        i += 110 + nlen; i += (4 - i % 4) % 4
        i += size; i += (4 - i % 4) % 4
        if name == "TRAILER!!!":
            continue
        kind = {0o040000: "d", 0o120000: "l", 0o020000: "c"}.get(mode & 0o170000, "-")
        print("%s\t%s\t%s\t%d" % (tag, kind, name, size))
walk(raw, "plain")
PY
}

misl_initramfs_write_init() {
  cat >"$1" <<'INIT'
#!/bin/sh
# MIS Linux installed-system /init (misl initramfs). Not the live ISO init.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mkdir -p /run && mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run

root= fstype= flags= mode=ro init=/sbin/init shell=0 fsck=0 timeout=30 quiet=0
for a in $(cat /proc/cmdline); do
  case $a in
    root=*) root=${a#root=} ;;
    rootfstype=*) fstype=${a#rootfstype=} ;;
    rootflags=*) flags=${a#rootflags=} ;;
    ro) mode=ro ;;
    rw) mode=rw ;;
    init=*) init=${a#init=} ;;
    quiet) quiet=1 ;;
    rd.misl.shell|rd.misl.shell=1) shell=1 ;;
    rd.misl.debug|rd.misl.debug=1) set -x ;;
    rd.misl.fsck|rd.misl.fsck=1) fsck=1 ;;
    rd.misl.timeout=*) timeout=${a#rd.misl.timeout=} ;;
  esac
done

say() { [ "$quiet" = 1 ] || printf 'misl initramfs: %s\n' "$*"; }

rescue() {
  printf '\nmisl initramfs: %s\n' "$*"
  printf 'misl initramfs: cmdline: %s\n' "$(cat /proc/cmdline)"
  printf 'misl initramfs: block devices:\n'
  blkid 2>/dev/null || cat /proc/partitions
  printf 'misl initramfs: modules: /etc/misl/initramfs.modules (lsmod: cat /proc/modules)\n'
  printf 'misl initramfs: rescue shell. mount the root on /newroot and exit to continue\n'
  sh -i </dev/console >/dev/console 2>&1 || sh
}

say "kernel $(cat /proc/sys/kernel/osrelease)"
if [ -f /etc/misl/initramfs.modules ]; then
  while read -r name path; do
    case $path in builtin|missing|"") continue ;; esac
    modprobe -q "$name" 2>/dev/null || insmod "/lib/modules/$(cat /etc/misl/modver)/$path" 2>/dev/null || true
  done </etc/misl/initramfs.modules
fi

[ "$shell" = 1 ] && rescue "rd.misl.shell on the kernel cmdline"

find_root() {
  case $root in
    UUID=*|PARTUUID=*|LABEL=*|PARTLABEL=*) blkid -l -o device -t "$root" 2>/dev/null ;;
    /dev/*) [ -b "$root" ] && printf '%s\n' "$root" ;;
  esac
}

# $init is often an absolute symlink (/sbin/init -> /usr/lib/systemd/...),
# so test -L too: it resolves against the initramfs, not /newroot.
has_init() { [ -x "/newroot$init" ] || [ -L "/newroot$init" ]; }
while ! mountpoint -q /newroot 2>/dev/null && ! has_init; do
  [ -n "$root" ] || { rescue "no root= on the kernel cmdline"; continue; }
  dev= i=0
  while [ $i -lt $((timeout * 4)) ]; do
    dev=$(find_root)
    [ -n "$dev" ] && break
    sleep 0.25; i=$((i + 1))
  done
  [ -n "$dev" ] || { rescue "root $root not found after ${timeout}s (missing storage driver?)"; continue; }
  t=${fstype:-$(blkid -s TYPE -o value "$dev" 2>/dev/null)}
  [ -n "$t" ] && modprobe -q "$t" 2>/dev/null
  if [ "$fsck" = 1 ] && command -v "fsck.$t" >/dev/null 2>&1; then
    say "fsck.$t -p $dev"
    "fsck.$t" -p "$dev"
    [ $? -lt 4 ] || { rescue "fsck.$t $dev failed; run it by hand"; continue; }
  fi
  opts=$mode
  [ -n "$flags" ] && opts=$mode,$flags
  say "mount $dev ($t, $opts) on /newroot"
  mount ${t:+-t "$t"} -o "$opts" "$dev" /newroot || { rescue "mount $dev failed"; continue; }
  has_init || { umount /newroot; rescue "no $init on $dev"; continue; }
done

say "switch_root -> $init"
exec switch_root /newroot "$init"
rescue "switch_root failed"
INIT
  chmod 0755 "$1"
}

# Shared with iso pack: shell, mount tools and their libs from the
# guest root, merged-usr links kept, refuse without libc.so.6.
misl_initrd_userland() {
  local root=$1 ird=$2; shift 2
  local path real link tgt so guest
  for path in "$@"; do
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
    die "no shell in the image — cannot build initramfs"
  # LFS is merged-usr: /lib and /lib64 are symlinks to usr/lib. Copying
  # the interpreter as /lib64/ld-linux-*.so.2 turns lib64 into a directory
  # with only the loader — libc stays in /usr/lib and PID 1 exits 127.
  for link in /lib /lib64 /usr/lib64; do
    if [[ -L $root$link ]]; then
      tgt=$(readlink "$root$link")
      local abs
      if [[ $tgt == /* ]]; then abs=$ird$tgt; else abs=$ird$(dirname "$link")/$tgt; fi
      mkdir -p "$abs"
      # Keep what the walk put under the real dir (e.g. the loader).
      if [[ -d $ird$link && ! -L $ird$link ]]; then
        cp -a "$ird$link/." "$abs/"
      fi
      rm -rf "${ird:?}$link"
      mkdir -p "$ird$(dirname "$link")"
      ln -sfn "$tgt" "$ird$link"
    fi
  done
  # The NEEDED walk has been missing libc/readline on this tree. Copy
  # by name from the guest and refuse to pack without libc.so.6.
  for so in libc.so.6 libreadline.so.8 libhistory.so.8 libncursesw.so.6 \
            libncurses.so.6 libtinfo.so.6 libdl.so.2 libpthread.so.0 \
            libmount.so.1 libblkid.so.1 libuuid.so.1 libsystemd.so.0 \
            libcap.so.2 libcrypt.so.2; do
    guest=$(misl_iso_find_so "$root" "$so") || continue
    misl_iso_install_file "$root" "$ird" "$guest" || true
  done
  if [[ ! -e $ird/usr/lib/libc.so.6 && ! -e $ird/lib/libc.so.6 && ! -e $ird/lib64/libc.so.6 ]]; then
    # shellcheck disable=SC2012
    die "initramfs has no libc.so.6 (have: $(ls "$ird/usr/lib" 2>/dev/null | tr '\n' ' ')). guest usr/lib=$(ls "$root/usr/lib"/libc.so* 2>/dev/null | tr '\n' ' ')"
  fi
}

# Build against <root> ("" = /). Writes /boot files + ledger.
misl_initramfs_build_root() {
  local root=$1 kver=${2:-$MISL_INITRAMFS_KVER}
  local boot=$root/boot img ucode st ird early modver moddir
  local rp fw f nfw=0 nmiss=0 mods fwmiss=''
  img=$boot/initramfs-$kver.img
  ucode=$boot/microcode.img
  st=$(misl_initramfs_state "$root")
  require_cmd python3 gzip readelf
  [[ -d $boot ]] || die "no $boot"
  for f in "$img" "$ucode"; do
    if [[ -e $f && ${MISL_FORCE:-0} != 1 ]] && ! grep -qxF "${f#"$root"}" "$st/$kver.files" 2>/dev/null; then
      die "refusing to overwrite $f (not written by misl initramfs; MISL_FORCE=1)"
    fi
  done
  modver=$(misl_initramfs_modver "$root" "$kver")
  moddir=$root/lib/modules/$modver
  [[ -d $moddir ]] || die "no $moddir (build 10-boot/linux first)"

  ird=$(mktemp -d /tmp/misl-initramfs.XXXXXX)
  early=$(mktemp -d /tmp/misl-ucode.XXXXXX)
  mkdir -p "$ird"/{dev,proc,sys,run,tmp,newroot,etc/misl}
  misl_initrd_userland "$root" "$ird" \
    /usr/bin/bash /bin/bash /bin/sh \
    /usr/bin/mount /usr/bin/umount /usr/bin/mountpoint /usr/sbin/switch_root \
    /usr/bin/mkdir /usr/bin/sleep /usr/bin/cat /usr/bin/ls \
    /usr/sbin/modprobe /usr/sbin/insmod /usr/bin/kmod /usr/sbin/blkid \
    /usr/sbin/e2fsck /usr/sbin/fsck.ext4 /usr/bin/dmesg
  [[ -e $ird/usr/sbin/switch_root || -e $ird/sbin/switch_root ]] || \
    die "no switch_root in $root (util-linux)"
  [[ -e $ird/usr/sbin/blkid || -e $ird/sbin/blkid ]] || die "no blkid in $root (util-linux)"
  # After userland: /lib may now be the merged-usr link.
  mkdir -p "$ird/lib/firmware" "$ird/lib/modules/$modver"

  mapfile -t mods < <(misl_initramfs_requests)
  misl_initramfs_resolve "$moddir" "${mods[@]}" >"$ird/etc/misl/initramfs.modules"
  printf '%s\n' "$modver" >"$ird/etc/misl/modver"
  cp -a "$moddir"/modules.* "$ird/lib/modules/$modver/" 2>/dev/null || true
  [[ $modver == "$kver" ]] || ln -sfn "$modver" "$ird/lib/modules/$kver"
  while IFS=$'\t' read -r _ rp; do
    case $rp in
      builtin) continue ;;
      missing) nmiss=$((nmiss + 1)); continue ;;
    esac
    mkdir -p "$ird/lib/modules/$modver/$(dirname "$rp")"
    cp -a "$moddir/$rp" "$ird/lib/modules/$modver/$rp"
    while IFS= read -r fw; do
      [[ -n $fw ]] || continue
      f=$root$MISL_INITRAMFS_FW_STAGE/$fw
      if [[ -f $f ]]; then
        mkdir -p "$ird/lib/firmware/$(dirname "$fw")"
        cp -L "$f" "$ird/lib/firmware/$fw"
        nfw=$((nfw + 1))
      else
        fwmiss+=" $fw"
      fi
    done < <(misl_initramfs_ko_firmware "$moddir/$rp")
  done <"$ird/etc/misl/initramfs.modules"
  misl_initramfs_write_init "$ird/init"

  mkdir -p "$st"
  : >"$st/$kver.files.new"
  misl_initramfs_cpio "$ird" "dev/console:5:1:600 dev/null:1:3:666" | gzip -9n >"$img.new"
  mv -f "$img.new" "$img"
  printf '%s\n' "${img#"$root"}" >>"$st/$kver.files.new"
  if misl_initramfs_ucode_tree "$root" "$early"; then
    misl_initramfs_cpio "$early" >"$ucode.new"
    mv -f "$ucode.new" "$ucode"
    printf '%s\n' "${ucode#"$root"}" >>"$st/$kver.files.new"
  else
    rm -f "$ucode"
    warn "no microcode blobs (amd-ucode under $MISL_INITRAMFS_FW_STAGE, intel-ucode under /usr/share/misl/intel-ucode)"
  fi
  mv -f "$st/$kver.files.new" "$st/$kver.files"
  cp -f "$ird/etc/misl/initramfs.modules" "$st/$kver.modules"
  rm -rf "$ird" "$early"
  if [[ -n $fwmiss ]]; then
    # Modules list optional blobs too; only the staged tree is used.
    warn "firmware not in $MISL_INITRAMFS_FW_STAGE (not fetched):$fwmiss"
  fi
  info "initramfs ${img#"$root"} ($(du -h "$img" | cut -f1); $(grep -cv 'builtin\|missing' "$st/$kver.modules" || true) modules, $nfw firmware, $nmiss not built)"
}

misl_initramfs_remove_root() {
  local root=$1 kver=${2:-$MISL_INITRAMFS_KVER} st f
  st=$(misl_initramfs_state "$root")
  [[ -f $st/$kver.files ]] || { info "no initramfs ledger for $kver"; return 0; }
  while IFS= read -r f; do
    [[ -n $f ]] && rm -fv "$root$f"
  done <"$st/$kver.files"
  rm -f "$st/$kver.files" "$st/$kver.modules"
}

# GRUB entries. With an initramfs: main entry + "(no initramfs)" fallback.
# args: root bootprefix kver title cmd_initrd cmd_plain
misl_initramfs_grub_entries() {
  local root=$1 pfx=$2 kver=$3 title=$4 cmd_i=$5 cmd_p=$6 ird=""
  if misl_initramfs_enabled && [[ -f $root/boot/initramfs-$kver.img ]]; then
    [[ -f $root/boot/microcode.img ]] && ird="$pfx/microcode.img "
    ird+="$pfx/initramfs-$kver.img"
    printf 'menuentry "%s" {\n' "$title"
    printf '        linux %s/vmlinuz-%s %s\n' "$pfx" "$kver" "$cmd_i"
    printf '        initrd %s\n' "$ird"
    printf '}\n'
    printf 'menuentry "%s (no initramfs)" {\n' "$title"
  else
    printf 'menuentry "%s" {\n' "$title"
  fi
  printf '        linux %s/vmlinuz-%s %s\n' "$pfx" "$kver" "$cmd_p"
  printf '}\n'
}

# Build only when enabled; used by 10-boot/linux and 10-boot/grub.
misl_initramfs_auto() {
  if ! misl_initramfs_enabled; then
    info "MISL_INITRAMFS=0: no initramfs"
    return 0
  fi
  misl_initramfs_build_root "$1" "${2:-}"
}

misl_initramfs() {
  local sub=${1:-} root kver=${2:-$MISL_INITRAMFS_KVER} st
  shift || true
  require_lfs_set
  root=$(misl_dest)
  st=$(misl_initramfs_state "$root")
  case $sub in
    build)
      misl_initramfs_enabled || die "MISL_INITRAMFS=0"
      misl_initramfs_build_root "$root" "$kver"
      ;;
    list)
      [[ -f $st/$kver.files ]] || die "no initramfs for $kver (misl initramfs build)"
      printf '# modules (name, path|builtin|missing)\n'
      cat "$st/$kver.modules"
      local f
      while IFS= read -r f; do
        printf '# %s\n' "$f"
        misl_initramfs_cpio_list "$root$f"
      done <"$st/$kver.files"
      ;;
    remove) misl_initramfs_remove_root "$root" "$kver" ;;
    *) die "usage: misl initramfs build|list|remove [kver]" ;;
  esac
}
