#!/usr/bin/env bash
# Smoke test for lib/firmware.sh (overlay firmware.list) against a fake
# staged linux-firmware tree and a fake $LFS under /tmp. No root, no
# downloads. Checks: globs, directories, WHENCE-style symlinks,
# compressed variants, two overlays sharing files, undo, missing entries
# (file:line, MISL_FIRMWARE_LAX=1), refusal to overwrite unowned files,
# not-staged failure, and a byte-identical tree after undo.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/misl-firmware-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

mkdir -p "$work/repo/overlays"
cp -a "$REPO/lib" "$work/repo/"
mkov() {
  mkdir -p "$work/repo/overlays/$1"
  printf 'name=%s\ntitle=fw smoke %s\nclass=hardware\nrequires=\nparent=\npriority=50\nstatus=alpha\n' \
    "$1" "$1" >"$work/repo/overlays/$1/overlay.conf"
  cat >"$work/repo/overlays/$1/firmware.list"
}
mkov fwa <<'L'
# NIC + Wi-Fi
rtl_nic/rtl8125*            # glob
iwlwifi-cc-a0-*.ucode
iwlwifi-cc-a0-77.ucode      # staged only as .xz
amdgpu/navi10_sos.bin       # staged only as .zst
intel/ibt-hw-link.sfi       # WHENCE Link: -> ibt-20-1-3.sfi

rtl_nic/alias.fw            # link across dirs
L
mkov fwb <<'L'
rtl_nic/rtl8125b-2.fw
intel/                      # whole directory
L
mkov fwmiss <<'L'
rtl_nic/rtl8125b-2.fw
nope/absent-*.bin
L
mkov fwbad <<'L'
ok.bin
../etc/passwd
L
mkdir -p "$work/repo/overlays/terminal"
printf 'name=terminal\ntitle=base\nclass=terminal\nrequires=\nparent=\npriority=10\nstatus=stable\ndefault=1\n' \
  >"$work/repo/overlays/terminal/overlay.conf"
MISL_ROOT=$work/repo
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
for l in overlay firmware; do
  # shellcheck disable=SC1090
  . "$MISL_ROOT/lib/$l.sh" || fail "source lib/$l.sh"
done

R=$work/root
LFS=$R
export LFS
mkdir -p "$R/etc" "$R/usr/lib/firmware" "$R/var/lib/misl"
ln -s usr/lib "$R/lib"
printf 'mine' >"$R/usr/lib/firmware/regulatory.db"   # pre-existing, not misl's

# 1. Not staged: clear failure, nothing written.
if (misl_overlay_apply fwa) >"$work/log" 2>&1; then fail "applied without staged tree"; fi
grep -q 'not staged' "$work/log" || fail "not-staged message: $(cat "$work/log")"
[[ -z $(find "$R/usr/lib/firmware" -mindepth 1 ! -name regulatory.db) ]] || fail "wrote before staging"
misl_overlay_applied fwa && fail "stamped although firmware failed"
ok "firmware.list before linux-firmware is staged: fails, writes nothing"

S=$R/usr/share/misl/linux-firmware
mkdir -p "$S/rtl_nic" "$S/intel" "$S/amdgpu"
for f in rtl_nic/rtl8125a-3.fw rtl_nic/rtl8125b-2.fw rtl_nic/rtl8168h-2.fw \
  iwlwifi-cc-a0-72.ucode intel/ibt-20-1-3.sfi intel/ibt-20-1-3.ddc; do
  printf 'blob:%s' "$f" >"$S/$f"
done
printf 'xz' >"$S/iwlwifi-cc-a0-77.ucode.xz"
printf 'zst' >"$S/amdgpu/navi10_sos.bin.zst"
ln -s ibt-20-1-3.sfi "$S/intel/ibt-hw-link.sfi"
ln -s ../intel/ibt-20-1-3.ddc "$S/rtl_nic/alias.fw"
printf 'File: x\n' >"$S/WHENCE"
printf '20261019\n' >"$S/.misl-version"

snap() { (cd "$R" && find . ! -path './var/lib/misl/overlays*' ! -path ./etc/os-release -printf '%y %p %l\n' | sort
          find . -type f ! -path './var/lib/misl/overlays*' ! -path ./etc/os-release -exec sha256sum {} + | sort -k2); }
snap >"$work/before"

# 2. Parser errors carry file:line.
if (misl_fw_list_parse "$work/repo/overlays/fwbad/firmware.list") >/dev/null 2>"$work/err"; then fail "'..' accepted"; fi
grep -q 'fwbad/firmware.list:2' "$work/err" || fail "parse error lacks file:line"
ok "bad firmware.list path: file:line"

# 3. Apply fwa.
(misl_overlay_apply fwa) >"$work/log" 2>&1 || { cat "$work/log"; fail "apply fwa"; }
F=$R/usr/lib/firmware
for f in rtl_nic/rtl8125a-3.fw rtl_nic/rtl8125b-2.fw iwlwifi-cc-a0-72.ucode iwlwifi-cc-a0-77.ucode.xz \
  amdgpu/navi10_sos.bin.zst intel/ibt-20-1-3.sfi intel/ibt-20-1-3.ddc; do
  [[ -f $F/$f && ! -L $F/$f ]] || fail "fwa: missing file $f"
done
[[ ! -e $F/rtl_nic/rtl8168h-2.fw ]] || fail "glob too wide (rtl8168h)"
[[ $(readlink "$F/intel/ibt-hw-link.sfi") == ibt-20-1-3.sfi ]] || fail "link not kept as symlink"
[[ -e $F/rtl_nic/alias.fw && -L $F/rtl_nic/alias.fw ]] || fail "cross-dir link dangling or copied"
[[ $(cat "$F/regulatory.db") == mine ]] || fail "touched unrelated file"
ok "fwa: globs, .xz/.zst variants, symlinks + their targets, nothing else"

# 4. Status / list commands.
misl_fw_status >"$work/st"
grep -q 'staged: 20261019' "$work/st" && grep -qP 'fwa\s+7 files, 2 links' "$work/st" || { cat "$work/st"; fail "status"; }
misl_fw_list fwa >"$work/ls"
grep -q '^installed .*/usr/lib/firmware/intel/ibt-hw-link.sfi' "$work/ls" || { cat "$work/ls"; fail "list"; }
misl_overlay_status | grep 'linux-firmware staged' >/dev/null || fail "overlay status lacks firmware"
ok "firmware status / list, and overlay status includes it"

# 5. Shared ownership: fwb shares rtl8125b + intel/.
(misl_overlay_apply fwb) >"$work/log" 2>&1 || { cat "$work/log"; fail "apply fwb"; }
(misl_overlay_undo fwa) >"$work/log" 2>&1 || { cat "$work/log"; fail "undo fwa"; }
[[ -f $F/rtl_nic/rtl8125b-2.fw && -f $F/intel/ibt-20-1-3.sfi && -L $F/intel/ibt-hw-link.sfi ]] || fail "undo fwa removed fwb's files"
[[ ! -e $F/rtl_nic/rtl8125a-3.fw && ! -e $F/iwlwifi-cc-a0-72.ucode && ! -e $F/amdgpu ]] || fail "undo fwa left its own files"
[[ ! -e $F/rtl_nic/alias.fw ]] || fail "undo fwa left alias link"
ok "undo fwa keeps files fwb still owns, removes the rest (and amdgpu/)"
(misl_overlay_undo fwb) >"$work/log" 2>&1 || { cat "$work/log"; fail "undo fwb"; }
snap >"$work/after"
diff -u "$work/before" "$work/after" || fail "tree differs after apply+undo"
ok "apply fwa, fwb; undo fwa, fwb: tree byte-identical"

# 6. Missing entries.
if (misl_overlay_apply fwmiss) >"$work/log" 2>&1; then fail "missing entry accepted"; fi
grep -q 'fwmiss/firmware.list:2: nope/absent-\*.bin' "$work/log" || { cat "$work/log"; fail "missing file:line"; }
[[ ! -e $F/rtl_nic ]] || fail "wrote despite missing entry"
(MISL_FIRMWARE_LAX=1 misl_overlay_apply fwmiss) >"$work/log" 2>&1 || { cat "$work/log"; fail "LAX apply"; }
grep -q 'MISL_FIRMWARE_LAX=1: skipped' "$work/log" && [[ -f $F/rtl_nic/rtl8125b-2.fw ]] || fail "LAX"
(misl_overlay_undo fwmiss) >/dev/null 2>&1
ok "missing entry: file:line error; MISL_FIRMWARE_LAX=1 warns and installs the rest"

# 7. Unowned file in the way.
mkdir -p "$F/intel"; printf 'hand' >"$F/intel/ibt-20-1-3.ddc"
if (misl_overlay_apply fwb) >"$work/log" 2>&1; then fail "overwrote unowned"; fi
grep -q 'refusing to overwrite /usr/lib/firmware/intel/ibt-20-1-3.ddc' "$work/log" || { cat "$work/log"; fail "refusal msg"; }
[[ $(cat "$F/intel/ibt-20-1-3.ddc") == hand && ! -e $F/rtl_nic ]] || fail "partial write on refusal"
(MISL_FORCE=1 misl_overlay_apply fwb) >/dev/null 2>&1 || fail "MISL_FORCE apply"
[[ $(cat "$F/intel/ibt-20-1-3.ddc") == blob:intel/ibt-20-1-3.ddc ]] || fail "MISL_FORCE did not overwrite"
ok "unowned file: refused (nothing written); MISL_FORCE=1 overwrites and owns"
printf 'firmware-smoke: all ok\n'
