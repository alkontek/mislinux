#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Smoke test for misl reset and the one-way cloud overlay, against a
# fake $LFS and a fake staged linux-firmware under /tmp. No root, no
# downloads (MISL_FETCH=0). Applies desktop + rog-strix-x570 and
# cloud/do on a base tree, then checks: the snapshot is taken on the
# first apply, the cloud notice, cloud undo refused, reset refuses
# without confirmation or without a snapshot, and after
# MISL_FORCE=1 reset the tree is byte-identical to the base (except the
# kept snapshot) with no overlay stamps. Reset runs twice.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/misl-reset-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

mkdir -p "$work/repo/overlays"
cp -a "$REPO/lib" "$work/repo/"
cp -a "$REPO/overlays/terminal" "$REPO/overlays/desktop" "$REPO/overlays/cloud" "$work/repo/overlays/"
MISL_ROOT=$work/repo
MISL_FETCH=0
export MISL_ROOT MISL_FETCH
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
for l in overlay firmware reset cloud; do
  # shellcheck disable=SC1090
  . "$MISL_ROOT/lib/$l.sh" || fail "source lib/$l.sh"
done
ROG=desktop/asus/rog-strix-x570

R=$work/root
LFS=$R
export LFS
# Fake base as 09-config leaves it.
mkdir -p "$R/etc/ssh/sshd_config.d" "$R/etc/systemd/network" "$R/etc/systemd/system" \
  "$R/etc/modprobe.d" "$R/usr/lib/firmware" "$R/usr/lib/systemd/system" \
  "$R/usr/share/doc" "$R/var/lib/misl" "$R/root" "$R/home/igal"
printf 'root:x:0:0:root:/root:/bin/bash\n' >"$R/etc/passwd"
printf 'root:!:20000::::::\n' >"$R/etc/shadow"
printf 'root:x:0:\ntty:x:5:\n' >"$R/etc/group"
chmod 0600 "$R/etc/shadow"
printf 'Port 22\nUsePAM yes\n' >"$R/etc/ssh/sshd_config"
printf 'AuthorizedKeysCommand none\n' >"$R/etc/ssh/sshd_config.d/20-systemd-userdb.conf"
printf '[Match]\nName=en* eth*\n\n[Network]\nDHCP=yes\n' >"$R/etc/systemd/network/20-dhcp.network"
for u in sshd.service systemd-networkd.service systemd-resolved.service \
  cloud-init.service serial-getty@.service; do
  printf '[Unit]\n' >"$R/usr/lib/systemd/system/$u"
done
printf 'NAME="MIS Linux"\nMISL_OVERLAYS="terminal"\n' >"$R/usr/lib/os-release"
ln -s ../usr/lib/os-release "$R/etc/os-release"
printf 'notes\n' >"$R/home/igal/notes.txt"

S=$R/usr/share/misl/linux-firmware
mkdir -p "$S/rtl_nic" "$S/intel"
for f in rtl_nic/rtl8125a-3.fw rtl_nic/rtl8125b-2.fw rtl_nic/rtl8168h-2.fw \
  iwlwifi-cc-a0-72.ucode iwlwifi-cc-a0-77.ucode iwlwifi-ty-a0-gf-a0-83.ucode \
  intel/ibt-20-1-3.sfi intel/ibt-20-1-3.ddc intel/ibt-19-0-4.sfi; do
  printf 'fw %s\n' "$f" >"$S/$f"
done
printf '20261019\n' >"$S/.misl-version"

snap() { (cd "$R" && find . ! -path './var/lib/misl/reset*' -printf '%y %m %p %l\n' | sort
          find . -type f ! -path './var/lib/misl/reset*' -exec sha256sum {} + | sort -k2); }
snap >"$work/before"

# 1. No snapshot yet: info says so, reset refuses.
misl_reset_info >"$work/info" 2>&1 || fail "reset --info"
grep 'reset snapshot: none' "$work/info" >/dev/null || { cat "$work/info"; fail "info without snapshot"; }
if (MISL_FORCE=1 misl_reset_run) >"$work/log" 2>&1; then fail "reset ran without a snapshot"; fi
grep 'no reset snapshot' "$work/log" >/dev/null || { cat "$work/log"; fail "no-snapshot message"; }
ok "reset without a snapshot refused"

# 2. First apply takes the snapshot (before writing anything).
(misl_overlay_apply "$ROG") >"$work/log" 2>&1 || { cat "$work/log"; fail "apply $ROG"; }
misl_reset_have || fail "no snapshot after first apply"
grep -x 'path=etc' "$R/var/lib/misl/reset/manifest" >/dev/null || fail "manifest lacks etc"
grep -x 'absent=var/lib/cloud' "$R/var/lib/misl/reset/manifest" >/dev/null || fail "manifest lacks absent var/lib/cloud"
tar -tzf "$R/var/lib/misl/reset/pre-overlay.tar.gz" | grep -x 'etc/shadow' >/dev/null || fail "snapshot lacks etc/shadow"
tar -tzf "$R/var/lib/misl/reset/pre-overlay.tar.gz" | grep '^var/lib/misl/overlays/.*applied' >/dev/null \
  && fail "snapshot holds an overlay stamp"
cp "$R/var/lib/misl/reset/manifest" "$work/manifest1"
ok "snapshot taken on first apply"

# 3. cloud/do: notice printed, one-way edits made, no new snapshot.
(misl_overlay_apply cloud/do) >"$work/log" 2>&1 || { cat "$work/log"; fail "apply cloud/do"; }
grep 'NOTICE: cloud is a one-way overlay' "$work/log" >/dev/null || { cat "$work/log"; fail "cloud notice"; }
grep 'way back is ./misl reset' "$work/log" >/dev/null || fail "notice names reset"
[[ $(grep -c 'NOTICE: cloud' "$work/log") == 1 ]] || fail "notice printed more than once"
grep -x 'root:\*:20000::::::' "$R/etc/shadow" >/dev/null || fail "root not '*'"
grep -x 'wheel:x:97:' "$R/etc/group" >/dev/null || fail "wheel group"
[[ -f $R/etc/sudoers.d/wheel && -L $R/etc/resolv.conf ]] || fail "sudoers/resolv.conf"
[[ ! -e $R/etc/ssh/sshd_config.d/20-systemd-userdb.conf ]] || fail "userdb conf kept"
[[ ! -e $R/etc/ssh/sshd_config.d/20-systemd-userdb.conf.misl ]] || fail "userdb stash left"
[[ ! -e $R/var/lib/misl/cloud.wanted ]] || fail "cloud.wanted written"
cmp -s "$work/manifest1" "$R/var/lib/misl/reset/manifest" || fail "snapshot retaken"
misl_overlay_kernel_wanted || fail "kernel extras not wanted with cloud applied"
ok "cloud apply: notice, edits in place"

# 4. One-way: overlay undo and cloud undo refuse.
for args in "misl_overlay_undo cloud/do" "misl_overlay_undo cloud" "misl_cloud undo"; do
  if ($args) >"$work/log" 2>&1; then fail "$args succeeded"; fi
  grep 'is one-way and cannot be undone' "$work/log" >/dev/null || { cat "$work/log"; fail "$args message"; }
  grep 'run ./misl reset' "$work/log" >/dev/null || fail "$args does not name reset"
done
misl_overlay_applied cloud/do || fail "cloud/do stamp lost by refused undo"
misl_overlay_applied cloud || fail "cloud stamp lost by refused undo"
cp "$work/log" "$work/refusal"
misl_overlay_list --no-header >"$work/list"
grep -P '^cloud/do\s.*\[one-way\]' "$work/list" >/dev/null || { cat "$work/list"; fail "list one-way"; }
grep -P '^desktop\s.*\[one-way\]' "$work/list" >/dev/null && fail "desktop marked one-way"
misl_overlay_status >"$work/st" 2>&1 || true
grep 'cloud .*one-way' "$work/st" >/dev/null || { cat "$work/st"; fail "status one-way"; }
grep 'reset snapshot: yes' "$work/st" >/dev/null || fail "status snapshot"
ok "cloud undo refused (overlay undo, cloud undo); list/status show one-way"

# 5. Stray files under restored paths; reset needs confirmation.
printf 'x\n' >"$R/etc/stray.conf"
mkdir -p "$R/root/.cache" && printf 'x\n' >"$R/root/.cache/y"
if (misl_reset_run </dev/null) >"$work/log" 2>&1; then fail "reset without confirmation"; fi
grep 'needs confirmation' "$work/log" >/dev/null || { cat "$work/log"; fail "confirm message"; }
[[ -f $R/etc/sudoers.d/wheel ]] || fail "reset wrote before confirmation"
misl_reset_info >"$work/info" 2>&1 || fail "reset --info"
grep -F '    /etc' "$work/info" >/dev/null || { cat "$work/info"; fail "info lacks /etc"; }
grep -F "    $ROG" "$work/info" >/dev/null || { cat "$work/info"; fail "info lacks $ROG"; }
ok "reset refuses without yes / MISL_FORCE=1; --info lists paths and overlays"

# 6. Reset: byte-identical, stamps cleared, snapshot kept; twice.
for n in 1 2; do
  (MISL_FORCE=1 misl_reset_run </dev/null) >"$work/log" 2>&1 || { cat "$work/log"; fail "reset $n"; }
  snap >"$work/after"
  diff -u "$work/before" "$work/after" || fail "tree differs after reset $n"
  find "$R/var/lib/misl" -name applied | grep . >/dev/null && fail "stamps left after reset $n"
  misl_reset_have || fail "snapshot not kept"
  grep -x 'MISL_OVERLAYS="terminal"' "$R/usr/lib/os-release" >/dev/null || fail "os-release overlays"
  [[ $n == 1 ]] && { (misl_overlay_apply desktop) >/dev/null 2>&1 || fail "re-apply desktop"; }
done
ok "reset is byte-exact, clears stamps, keeps the snapshot, repeats"

# 7. Desktop-only undo still byte-exact on a reset tree.
(misl_overlay_apply desktop) >/dev/null 2>&1 || fail "apply desktop"
(misl_overlay_undo desktop) >/dev/null 2>&1 || fail "undo desktop"
# Undo keeps the empty state root (as in desktop-overlay-smoke).
snap | grep -v ' \./var/lib/misl/overlays $' >"$work/after"
diff -u "$work/before" "$work/after" || fail "desktop undo not exact"
ok "file-only undo stays exact"

sed -n 1p "$work/refusal"
printf 'reset-smoke: all ok\n'
