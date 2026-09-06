#!/usr/bin/env bash
# Smoke test for lib/initramfs.sh against a fake /tmp root (no root, no
# downloads, no build). Host bash/mount/blkid/switch_root and their libs
# stand in for the target userland; modules, modules.dep, firmware and
# amd-ucode are fake. Checks: cpio listings, microcode-first initrd
# lines, overlay initramfs.list, ledger/remove, MISL_INITRAMFS=0, and the
# refusal to overwrite unowned /boot files.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/misl-initramfs-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

# Fake repo: real lib/, one fake overlay with an initramfs.list.
mkdir -p "$work/repo/overlays/smoke"
cp -a "$REPO/lib" "$work/repo/"
cat >"$work/repo/overlays/smoke/overlay.conf" <<'C'
name=smoke
title=initramfs smoke
class=hardware
requires=
parent=
priority=50
status=alpha
C
printf '# NIC for netboot\nr8169   # realtek\n\nnot_there\n' >"$work/repo/overlays/smoke/initramfs.list"
MISL_ROOT=$work/repo
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
for l in overlay chroot iso initramfs; do
  # shellcheck disable=SC1090
  . "$MISL_ROOT/lib/$l.sh" || fail "source lib/$l.sh"
done

R=$work/root
LFS=$R
export LFS
K=7.1.8-misl
M=$R/usr/lib/modules/$K
mkdir -p "$R/boot" "$R/usr/bin" "$R/usr/sbin" "$R/usr/lib" "$M/kernel/drivers" \
  "$R/usr/share/misl/linux-firmware/rtl_nic" "$R/usr/share/misl/linux-firmware/amd-ucode" \
  "$R/var/lib/misl/overlays/smoke"
ln -s usr/bin "$R/bin"; ln -s usr/sbin "$R/sbin"; ln -s usr/lib "$R/lib"; ln -s usr/lib "$R/lib64"
: >"$R/var/lib/misl/overlays/smoke/applied"

# Host binaries + libs as the target userland.
for b in bash mount umount mountpoint switch_root mkdir sleep cat ls blkid dmesg; do
  p=$(PATH=$PATH:/usr/sbin:/sbin command -v "$b" 2>/dev/null || true)
  [[ -n $p ]] || continue
  case $b in switch_root|blkid) d=usr/sbin ;; *) d=usr/bin ;; esac
  cp -L "$p" "$R/$d/$b"
  while read -r lib; do
    [[ -f $lib ]] && cp -Ln "$lib" "$R/usr/lib/" 2>/dev/null || true
  done < <(ldd "$p" 2>/dev/null | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p; s/^[[:space:]]*\(\/[^ ]*\) .*/\1/p')
done
[[ -e $R/usr/lib/libc.so.6 ]] || fail "host libc.so.6 not copied"
# A script (non-ELF) tool must not break the lib walk.
printf '#!/bin/sh\necho fake\n' >"$R/usr/sbin/modprobe"; chmod +x "$R/usr/sbin/modprobe"

# Fake modules: r8169 -> libphy, ahci as .ko.xz, nvme builtin.
mkko() { mkdir -p "$(dirname "$M/$1")"; printf 'ELFfake\0%s\0' "$2" >"$M/$1"; }
mkko kernel/drivers/net/r8169.ko 'firmware=rtl_nic/rtl8125a-3.fw'
mkko kernel/drivers/net/libphy.ko 'license=GPL'
mkko kernel/drivers/ata/libahci.ko 'license=GPL'
mkko kernel/drivers/ata/ahci.ko 'firmware=rtl_nic/absent.fw'
cat >"$M/modules.dep" <<'D'
kernel/drivers/net/r8169.ko: kernel/drivers/net/libphy.ko
kernel/drivers/net/libphy.ko:
kernel/drivers/ata/ahci.ko: kernel/drivers/ata/libahci.ko
kernel/drivers/ata/libahci.ko:
D
printf 'kernel/drivers/nvme/host/nvme.ko\nkernel/fs/ext4/ext4.ko\n' >"$M/modules.builtin"
printf 'fw' >"$R/usr/share/misl/linux-firmware/rtl_nic/rtl8125a-3.fw"
printf 'AMDUCODE1' >"$R/usr/share/misl/linux-firmware/amd-ucode/microcode_amd_fam17h.bin"
printf 'AMDUCODE2' >"$R/usr/share/misl/linux-firmware/amd-ucode/microcode_amd_fam19h.bin"
: >"$R/boot/vmlinuz-$K"

# 1. Parser rejects junk with file:line.
printf 'good\nbad/name\n' >"$work/bad.list"
if (misl_initramfs_list_parse "$work/bad.list") >/dev/null 2>"$work/err"; then fail "bad list accepted"; fi
grep -q 'bad.list:2' "$work/err" || fail "parse error lacks file:line: $(cat "$work/err")"
ok "initramfs.list parse errors carry file:line"

# 2. Build.
(misl_initramfs_build_root "$R" "$K") >"$work/build.log" 2>&1 || { cat "$work/build.log"; fail "build"; }
[[ -f $R/boot/initramfs-$K.img && -f $R/boot/microcode.img ]] || fail "images missing"
ok "build: $(tail -1 "$work/build.log")"

misl_initramfs_cpio_list "$R/boot/initramfs-$K.img" >"$work/main.lst"
misl_initramfs_cpio_list "$R/boot/microcode.img" >"$work/ucode.lst"
has() { grep -qP "\t$2(\t|$)" "$1" || fail "$(basename "$1") lacks $2"; }
for e in init dev/console dev/null etc/misl/initramfs.modules usr/sbin/switch_root usr/sbin/blkid \
  usr/lib/libc.so.6 "usr/lib/modules/$K/modules.dep" \
  "usr/lib/modules/$K/kernel/drivers/net/r8169.ko" "usr/lib/modules/$K/kernel/drivers/net/libphy.ko" \
  "usr/lib/modules/$K/kernel/drivers/ata/ahci.ko" "usr/lib/firmware/rtl_nic/rtl8125a-3.fw"; do
  has "$work/main.lst" "$e"
done
grep -qP '^gz\t' "$work/main.lst" || fail "main image not gzip"
ok "main initramfs: init, devs, userland, deps-first modules, staged firmware"
grep -q 'absent.fw' "$work/build.log" || fail "missing firmware not reported"
ok "missing firmware is reported, not fetched"

has "$work/ucode.lst" kernel/x86/microcode/AuthenticAMD.bin
grep -qvP '^plain\t' "$work/ucode.lst" && fail "microcode.img must be uncompressed cpio"
python3 - "$R/boot/microcode.img" <<'P' || fail "AuthenticAMD.bin is not the concatenated blobs"
import sys; d=open(sys.argv[1],'rb').read(); i=d.index(b'AMDUCODE1'); assert d[i:i+18]==b'AMDUCODE1AMDUCODE2'
P
ok "microcode.img: plain newc, AuthenticAMD.bin = fam17h+fam19h"

mods=$(grep -v '^#' "$R/var/lib/misl/initramfs/$K.modules")
grep -qP '^libphy\t' <<<"$mods" || fail "libphy (dep) not resolved"
[[ $(grep -nP '^libphy\t' <<<"$mods" | cut -d: -f1) -lt $(grep -nP '^r8169\t' <<<"$mods" | cut -d: -f1) ]] || fail "deps not first"
grep -qP '^nvme\tbuiltin' <<<"$mods" || fail "nvme not seen as builtin"
grep -qP '^not_there\tmissing' <<<"$mods" || fail "missing module not recorded"
ok "modules.dep order (libphy before r8169), nvme builtin, overlay list honoured"

# 3. GRUB entries: microcode first; fallback entry without initrd.
misl_initramfs_grub_entries "$R" /boot "$K" "MIS Linux" "root=UUID=u ro" "root=PARTUUID=p ro" >"$work/grub.cfg"
grep -qx "        initrd /boot/microcode.img /boot/initramfs-$K.img" "$work/grub.cfg" || { cat "$work/grub.cfg"; fail "initrd line"; }
grep -q 'menuentry "MIS Linux (no initramfs)"' "$work/grub.cfg" || fail "fallback entry"
[[ $(grep -c '^        initrd' "$work/grub.cfg") == 1 ]] || fail "fallback must have no initrd"
grep -A2 'no initramfs' "$work/grub.cfg" | grep -q 'root=PARTUUID=p' || fail "fallback must use PARTUUID"
misl_initramfs_grub_entries "$R" "" "$K" "MIS Linux" "root=PARTUUID=p ro" "root=PARTUUID=p ro" >"$work/img.cfg"
grep -qx "        initrd /microcode.img /initramfs-$K.img" "$work/img.cfg" || fail "img (separate /boot) initrd line"
ok "grub.cfg: initrd microcode.img before initramfs; PARTUUID fallback entry"
MISL_INITRAMFS=0 misl_initramfs_grub_entries "$R" /boot "$K" "MIS Linux" "root=UUID=u ro" "root=PARTUUID=p ro" >"$work/off.cfg"
[[ $(grep -c menuentry "$work/off.cfg") == 1 ]] && ! grep -q initrd "$work/off.cfg" || fail "MISL_INITRAMFS=0 grub"
(MISL_INITRAMFS=0 misl_initramfs_auto "$R" "$K") >/dev/null 2>&1
ok "MISL_INITRAMFS=0: one entry, no initrd, auto is a no-op"

# 4. Init script sanity.
python3 - "$R/boot/initramfs-$K.img" "$work/init" <<'P'
import gzip,sys
d=gzip.open(sys.argv[1]).read(); o=0
while True:
    h=d[o:o+110]; n=int(h[94:102],16); s=int(h[54:62],16)
    name=d[o+110:o+110+n-1].decode(); o=(o+110+n+3)&~3
    if name=='init': open(sys.argv[2],'wb').write(d[o:o+s]); break
    o=(o+s+3)&~3
P
bash -n "$work/init" || fail "init syntax"
for w in 'root=' 'rootfstype=' 'rootflags=' 'rd.misl.shell' 'rd.misl.fsck' 'switch_root' 'PARTUUID'; do
  grep -q -- "$w" "$work/init" || fail "init lacks $w"
done
ok "init: bash -n clean; root/rootfstype/rootflags/rd.misl.*/switch_root"

# 5. Unowned files are not overwritten; ledger remove.
mkdir -p "$work/r2/boot"; cp -a "$R/." "$work/r2/"
rm -rf "$work/r2/var/lib/misl/initramfs"
if (LFS=$work/r2 misl_initramfs_build_root "$work/r2" "$K") >/dev/null 2>&1; then fail "overwrote unowned initramfs"; fi
ok "refuses to overwrite an initramfs it did not write"
(misl_initramfs_build_root "$R" "$K") >/dev/null 2>&1 || fail "rebuild of owned files"
(misl_initramfs_remove_root "$R" "$K") >/dev/null 2>&1 || fail "remove"
[[ ! -e $R/boot/initramfs-$K.img && ! -e $R/boot/microcode.img && ! -e $R/var/lib/misl/initramfs/$K.files ]] || fail "remove left files"
ok "rebuild owned + remove via ledger"
printf 'initramfs-smoke: all ok\n'
