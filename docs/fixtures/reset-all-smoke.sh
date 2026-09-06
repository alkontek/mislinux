#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Smoke test for misl reset --all against a fake $LFS, a fake
# MISL_SNAPSHOT and a fake /var/tmp under /tmp. No root, no downloads,
# no real mounts: MISL_MOUNTINFO points at a fake mountinfo file.
# Checks: refuses empty LFS and LFS=/, refuses a snapshot inside $LFS,
# dies on an unexpected mount and on a built image inside $LFS, dry run
# deletes nothing, needs confirmation, and MISL_FORCE=1 empties $LFS
# but keeps lost+found, the boot mount point, the snapshot, and every
# *.img / *.img.gz / *.iso in the temp dir.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
[[ ${EUID:-$(id -u)} -ne 0 ]] || { printf 'reset-all-smoke: run as a normal user\n' >&2; exit 1; }
work=$(mktemp -d /tmp/misl-reset-all-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

MISL_ROOT=$REPO
MISL_SNAPSHOT=$work/cache/misl-1.0-systemd
MISL_RESET_TMPDIR=$work/vartmp
MISL_MOUNTINFO=$work/mountinfo
LFS=$work/lfs
export MISL_ROOT MISL_SNAPSHOT MISL_RESET_TMPDIR MISL_MOUNTINFO LFS
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
# shellcheck source=../../lib/reset.sh
. "$MISL_ROOT/lib/reset.sh"

mnt() { : >"$MISL_MOUNTINFO"; local m; for m in "$@"; do printf '1 1 0:1 / %s rw - x x rw\n' "$m" >>"$MISL_MOUNTINFO"; done; }
build_tree() {
  rm -rf "$LFS"
  mkdir -p "$LFS"/{tools/bin,usr/src/misl/SOURCES,var/lib/misl/stamps,boot/efi/EFI/BOOT,lost+found,etc}
  echo x >"$LFS/tools/bin/gcc"; echo x >"$LFS/usr/src/misl/SOURCES/a.tar.xz"
  echo x >"$LFS/var/lib/misl/stamps/a.done"; echo x >"$LFS/boot/efi/EFI/BOOT/BOOTX64.EFI"
  echo x >"$LFS/boot/initramfs-6.1.img"; echo x >"$LFS/.hidden"
  ln -s usr/lib "$LFS/lib"
}
mkdir -p "$MISL_SNAPSHOT/incoming/wheels" "$MISL_RESET_TMPDIR/misl-iso.abc/sub"
echo x >"$MISL_SNAPSHOT/a.tar.xz"; echo x >"$MISL_SNAPSHOT/incoming/wheels/w.whl"
echo x >"$MISL_RESET_TMPDIR/misl-iso.abc/sub/log"; echo x >"$MISL_RESET_TMPDIR/misl-iso.abc/out.iso"
echo x >"$MISL_RESET_TMPDIR/misl-0.4.img"; echo x >"$MISL_RESET_TMPDIR/misl-0.4-cloud-do.img.gz"
echo x >"$MISL_RESET_TMPDIR/misl-ovmf-vars.X"
build_tree; mnt "$LFS" "$LFS/boot/efi"
snap_before=$(cd "$MISL_SNAPSHOT" && find . | sort)

( LFS="" misl_reset_all --dry-run ) 2>/dev/null && fail "empty LFS accepted"
( LFS=/ misl_reset_all --dry-run ) 2>/dev/null && fail "LFS=/ accepted"
ok "refuses empty LFS and LFS=/"
( MISL_SNAPSHOT=$LFS/snap misl_reset_all --dry-run ) 2>/dev/null && fail "snapshot inside LFS accepted"
ok "refuses MISL_SNAPSHOT inside \$LFS"

before=$(cd "$work" && find . | sort)
out=$(misl_reset_all --dry-run 2>&1) || fail "dry run failed: $out"
[[ $(cd "$work" && find . | sort) == "$before" ]] || fail "dry run changed files"
grep -q "$LFS/tools" <<<"$out" || fail "dry run does not list tools"
grep -q "$LFS/boot/efi/EFI" <<<"$out" || fail "dry run does not list boot partition contents"
grep -q "lost+found" <<<"$out" && fail "dry run lists lost+found"
grep -q 'out.iso\|\.img' <<<"$out" && grep -q "$MISL_RESET_TMPDIR.*\.\(iso\|img\)" <<<"$out" && fail "dry run lists an image"
ok "dry run lists, deletes nothing"

( misl_reset_all </dev/null ) >/dev/null 2>&1 && fail "ran without confirmation"
[[ -f $LFS/tools/bin/gcc ]] || fail "unconfirmed run deleted files"
ok "needs confirmation"

mnt "$LFS" "$LFS/mnt/usb"
( MISL_FORCE=1 misl_reset_all ) >/dev/null 2>&1 && fail "unexpected mount accepted"
mnt "$LFS" "$LFS/proc"
( MISL_FORCE=1 misl_reset_all ) >/dev/null 2>&1 && fail "chroot mount without root accepted"
[[ -f $LFS/tools/bin/gcc ]] || fail "mount refusal deleted files"
ok "dies on unexpected mount; chroot mounts need root"

mnt "$LFS" "$LFS/boot/efi"
echo x >"$LFS/usr/src/misl-0.4.img"
( MISL_FORCE=1 misl_reset_all ) >/dev/null 2>&1 && fail "image inside LFS deleted"
[[ -f $LFS/usr/src/misl-0.4.img ]] || fail "image inside LFS gone"
rm -f "$LFS/usr/src/misl-0.4.img"
ok "refuses a built image inside \$LFS"

MISL_FORCE=1 misl_reset_all >/dev/null 2>&1 || fail "forced reset --all failed"
left=$(cd "$LFS" && find . | sort | tr '\n' ' ')
[[ $left == ". ./boot ./boot/efi ./lost+found " ]] || fail "left in LFS: $left"
[[ $(cd "$MISL_SNAPSHOT" && find . | sort) == "$snap_before" ]] || fail "snapshot changed"
for f in misl-iso.abc/out.iso misl-0.4.img misl-0.4-cloud-do.img.gz; do
  [[ -f $MISL_RESET_TMPDIR/$f ]] || fail "image $f deleted"
done
[[ ! -e $MISL_RESET_TMPDIR/misl-iso.abc/sub ]] || fail "temp log dir kept"
[[ ! -e $MISL_RESET_TMPDIR/misl-ovmf-vars.X ]] || fail "temp file kept"
ok "wipes \$LFS, keeps boot mount, lost+found, snapshot and images"

MISL_FORCE=1 misl_reset_all >/dev/null 2>&1 || fail "second reset --all failed"
ok "runs again on an empty tree"
printf 'reset-all-smoke: all ok\n'
