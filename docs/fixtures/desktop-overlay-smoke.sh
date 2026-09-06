#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Smoke test for overlays/desktop and desktop/asus/rog-strix-x570 (the
# real overlay trees) against a fake $LFS and a fake staged
# linux-firmware under /tmp. No root, no downloads. Checks: status
# alpha, kernel.list parses, firmware.list resolves, the ancestor is
# auto-applied, files/ installed and owned, refusal to overwrite an
# unowned file, a byte-identical tree after undo, and the img/iso
# default names (none, desktop/asus/rog-strix-x570, cloud/do, MISL_IMG_TAG).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/misl-desktop-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

mkdir -p "$work/repo/overlays"
cp -a "$REPO/lib" "$work/repo/"
cp -a "$REPO/overlays/terminal" "$REPO/overlays/desktop" "$REPO/overlays/cloud" "$work/repo/overlays/"
MISL_ROOT=$work/repo
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
for l in overlay firmware img iso; do
  # shellcheck disable=SC1090
  . "$MISL_ROOT/lib/$l.sh" || fail "source lib/$l.sh"
done
ROG=desktop/asus/rog-strix-x570
OV=$MISL_ROOT/overlays

R=$work/root
LFS=$R
export LFS
# Fake base as 09-config leaves it.
mkdir -p "$R/etc/systemd/network" "$R/etc/systemd/system" "$R/etc/modprobe.d" \
  "$R/usr/lib/firmware" "$R/usr/share/doc" "$R/var/lib/misl"
printf '[Match]\nName=en* eth*\n\n[Network]\nDHCP=yes\n' >"$R/etc/systemd/network/20-dhcp.network"
printf 'KEYMAP=us\n' >"$R/etc/vconsole.conf"
printf 'NAME="MIS Linux"\n' >"$R/etc/os-release"

# Fake staged linux-firmware.
S=$R/usr/share/misl/linux-firmware
mkdir -p "$S/rtl_nic" "$S/intel"
for f in rtl_nic/rtl8125a-3.fw rtl_nic/rtl8125b-2.fw rtl_nic/rtl8168h-2.fw \
  iwlwifi-cc-a0-72.ucode iwlwifi-cc-a0-77.ucode iwlwifi-ty-a0-gf-a0-83.ucode \
  intel/ibt-20-1-3.sfi intel/ibt-20-1-3.ddc intel/ibt-19-0-4.sfi; do
  printf 'fw %s\n' "$f" >"$S/$f"
done
printf '20261019\n' >"$S/.misl-version"

snap() { (cd "$R" && find . ! -path './var/lib/misl/overlays*' ! -path ./etc/os-release -printf '%y %m %p %l\n' | sort
          find . -type f ! -path './var/lib/misl/overlays*' ! -path ./etc/os-release -exec sha256sum {} + | sort -k2); }
snap >"$work/before"

# 1. Status alpha.
misl_overlay_list --no-header >"$work/list"
grep -P '^desktop\s+alpha\s' "$work/list" >/dev/null || { cat "$work/list"; fail "desktop not alpha"; }
grep -P "^$ROG\s+alpha\s" "$work/list" >/dev/null || { cat "$work/list"; fail "rog not alpha"; }
ok "status alpha (desktop, $ROG)"

# 2. kernel.list parses; no GPU driver requested.
misl_kernel_list_parse "$OV/$ROG/kernel.list" "$ROG" >"$work/kl" || fail "kernel.list parse"
for s in CONFIG_IGB=m CONFIG_R8169=m CONFIG_IWLMVM=m CONFIG_BT_HCIBTUSB=m \
  CONFIG_SND_HDA_INTEL=m CONFIG_FW_LOADER_COMPRESS_ZSTD=y CONFIG_AMD_IOMMU=y CONFIG_SENSORS_K10TEMP=m; do
  grep -P "^${s%=*}\t${s#*=}\t" "$work/kl" >/dev/null || fail "kernel.list lacks $s"
done
grep -E 'DRM|AMDGPU|NOUVEAU' "$work/kl" >/dev/null && fail "kernel.list requests a GPU driver"
ok "kernel.list parses ($(wc -l <"$work/kl") requests, no GPU)"

# 3. Apply the child only: desktop comes first automatically.
MISL_VERSION=0.4; export MISL_VERSION
name() { (cd "$work" && unset MISL_IMG MISL_ISO MISL_IMG_TAG; "$@") | sed "s|^$work/||"; }
[[ $(name misl_img_default_out) == misl-$MISL_VERSION.img ]] || fail "base img name: $(name misl_img_default_out)"
[[ $(name misl_iso_default_out) == misl-$MISL_VERSION.iso ]] || fail "base iso name"
ok "base name misl-$MISL_VERSION.img/.iso"
(misl_overlay_apply "$ROG") >"$work/log" 2>&1 || { cat "$work/log"; fail "apply $ROG"; }
misl_overlay_applied desktop || fail "ancestor desktop not applied"
misl_overlay_applied "$ROG" || fail "$ROG not applied"
ok "ancestor desktop auto-applied"
[[ $(name misl_img_default_out) == "misl-$MISL_VERSION-desktop-asus-rog-strix-x570.img" ]] || fail "rog img name: $(name misl_img_default_out)"
[[ $(name misl_iso_default_out) == "misl-$MISL_VERSION-desktop-asus-rog-strix-x570.iso" ]] || fail "rog iso name"
[[ $(MISL_IMG_TAG=test1 misl_img_default_out) == */misl-$MISL_VERSION-test1.img ]] || fail "MISL_IMG_TAG override"
(MISL_IMG_TAG=a/b misl_img_default_out) >/dev/null 2>&1 && fail "MISL_IMG_TAG with / accepted"
# Fake stamps for a second, unrelated chain: leaves sorted, joined with -.
sr=$(misl_overlay_state_root)
mkdir -p "$sr/cloud/do"; touch "$sr/cloud/applied" "$sr/cloud/do/applied"
[[ $(name misl_img_default_out) == "misl-$MISL_VERSION-cloud-do-desktop-asus-rog-strix-x570.img" ]] || fail "multi-leaf name: $(name misl_img_default_out)"
rm -f "$sr/desktop/asus/rog-strix-x570/applied" "$sr/desktop/applied"
[[ $(name misl_img_default_out) == "misl-$MISL_VERSION-cloud-do.img" ]] || fail "cloud/do name: $(name misl_img_default_out)"
touch "$sr/desktop/applied" "$sr/desktop/asus/rog-strix-x570/applied"
rm -rf "$sr/cloud"
ok "names: rog, cloud/do, multi-leaf, MISL_IMG_TAG"

# 4. Files installed, identical to the overlay trees, and owned.
for p in etc/systemd/network/30-wireless.network usr/share/doc/misl/desktop/README \
  usr/share/doc/misl/desktop/wpa_supplicant-IFACE.conf.example; do
  cmp -s "$OV/desktop/files/$p" "$R/$p" || fail "desktop $p"
done
[[ $(readlink "$R/etc/systemd/system/timers.target.wants/fstrim.timer") == /usr/lib/systemd/system/fstrim.timer ]] \
  || fail "fstrim.timer link (made by apply.sh)"
grep -qxF /etc/systemd/system/timers.target.wants/fstrim.timer "$R/var/lib/misl/overlays/desktop/owned" \
  || fail "fstrim.timer link not owned"
[[ ! -e $OV/desktop/files/etc/systemd/system/timers.target.wants ]] || fail "wants link shipped in files/"
for p in etc/systemd/network/10-rog-wired.network etc/systemd/network/25-rog-wireless.network \
  etc/modprobe.d/misl-rog-strix-x570.conf usr/share/doc/misl/rog-strix-x570/README; do
  cmp -s "$OV/$ROG/files/$p" "$R/$p" || fail "rog $p"
done
grep -qx 'Driver=igb r8169' "$R/etc/systemd/network/10-rog-wired.network" || fail "wired match"
grep -qx 'Driver=iwlwifi' "$R/etc/systemd/network/25-rog-wireless.network" || fail "wireless match"
grep -v '^#' "$R/etc/modprobe.d/misl-rog-strix-x570.conf" | grep . >/dev/null && fail "modprobe.d not all comments"
st=$R/var/lib/misl/overlays
grep -qxF /etc/systemd/network/30-wireless.network "$st/desktop/owned" || fail "desktop owned"
grep -qxF /usr/share/doc/misl/ "$st/desktop/owned" || fail "desktop owns new dir"
grep -qxF /etc/modprobe.d/ "$st/desktop/owned" "$st/$ROG/owned" && fail "owns pre-existing dir"
grep -qxF /etc/modprobe.d/misl-rog-strix-x570.conf "$st/$ROG/owned" || fail "rog owned"
cmp -s "$R/etc/systemd/network/20-dhcp.network" <(printf '[Match]\nName=en* eth*\n\n[Network]\nDHCP=yes\n') \
  || fail "base 20-dhcp.network touched"
ok "files installed and owned (base untouched)"

# 5. firmware.list resolves: exactly the board's files.
(cd "$R/usr/lib/firmware" && find . -type f | sed 's|^\./||' | sort) >"$work/fw"
printf '%s\n' intel/ibt-20-1-3.ddc intel/ibt-20-1-3.sfi iwlwifi-cc-a0-72.ucode \
  iwlwifi-cc-a0-77.ucode rtl_nic/rtl8125a-3.fw rtl_nic/rtl8125b-2.fw >"$work/fw.want"
diff -u "$work/fw.want" "$work/fw" || fail "firmware set"
misl_fw_list "$ROG" >"$work/fwl" 2>&1 || { cat "$work/fwl"; fail "firmware list"; }
ok "firmware.list resolves (6 files)"

misl_overlay_status >"$work/st" 2>&1 || true
grep "$ROG" "$work/st" >/dev/null || { cat "$work/st"; fail "overlay status"; }
ok "overlay status lists $ROG"

# 6. Undo is byte-exact (child first; parent blocked while child on).
if (misl_overlay_undo desktop) >"$work/log" 2>&1; then fail "undo desktop with child applied"; fi
(misl_overlay_undo "$ROG") >"$work/log" 2>&1 || { cat "$work/log"; fail "undo $ROG"; }
(misl_overlay_undo desktop) >"$work/log" 2>&1 || { cat "$work/log"; fail "undo desktop"; }
snap >"$work/after"
diff -u "$work/before" "$work/after" || fail "tree differs after undo"
[[ ! -e $R/etc/systemd/system/timers.target.wants/fstrim.timer && ! -L $R/etc/systemd/system/timers.target.wants/fstrim.timer ]] \
  || fail "fstrim.timer link left after undo"
ok "undo is byte-exact (fstrim.timer link removed)"

# 7. Refuses to overwrite an unowned file; MISL_FORCE=1 takes it.
printf 'mine\n' >"$R/etc/systemd/network/30-wireless.network"
if (misl_overlay_apply desktop) >"$work/log" 2>&1; then fail "overwrote unowned"; fi
grep 'refusing to overwrite' "$work/log" >/dev/null || { cat "$work/log"; fail "refusal message"; }
[[ $(cat "$R/etc/systemd/network/30-wireless.network") == mine ]] || fail "unowned file changed"
[[ ! -e $R/usr/share/doc/misl ]] || fail "wrote before refusing"
misl_overlay_applied desktop && fail "stamped after refusal"
(MISL_FORCE=1 misl_overlay_apply desktop) >/dev/null 2>&1 || fail "MISL_FORCE apply"
cmp -s "$OV/desktop/files/etc/systemd/network/30-wireless.network" "$R/etc/systemd/network/30-wireless.network" \
  || fail "MISL_FORCE did not install"
ok "unowned file refused; MISL_FORCE=1 overrides"

printf 'desktop-overlay-smoke: all ok\n'
