#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# kernel.list parse + apply + verify on a fake overlays tree, a fake LFS
# and a fake .config, with a small stand-in for scripts/config. No kernel
# tree, no root, nothing downloaded.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MISL_ROOT=$REPO
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$REPO/lib/common.sh"
# shellcheck source=../../lib/overlay.sh
. "$REPO/lib/overlay.sh"

work=$(mktemp -d /tmp/misl-klist-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }
refused() {
  local pat=$1 out
  shift
  if out=$( ("$@") 2>&1 ); then fail "not refused: $*"; fi
  [[ $out == *"$pat"* ]] || fail "wrong refusal: $* -> $out"
  ok "refused: $* ($pat)"
}

# Stand-in for the kernel's scripts/config (same flags, same output).
sc() {
  local f=$cfg op=$1 sym=$2 val=${3:-} new
  case $op in
    --enable) new="$sym=y" ;;
    --module) new="$sym=m" ;;
    --disable) new="# $sym is not set" ;;
    --set-str) new="$sym=\"$val\"" ;;
    --set-val) new="$sym=$val" ;;
    *) return 1 ;;
  esac
  grep -vE "^(${sym}=|# ${sym} is not set$)" "$f" >"$f.tmp" || true
  printf '%s\n' "$new" >>"$f.tmp"
  mv "$f.tmp" "$f"
}

# --- parse: every form, comments, whitespace, CONFIG_ optional
kl=$work/kernel.list
cat >"$kl" <<'L'
# comment

CONFIG_A
  B   
C=y
CONFIG_D=m
E=n
F="hello world"   # trailing comment
G="a#b"
H=123
I=-1
J=0x1F
K=y # inline
L
got=$(misl_kernel_list_parse "$kl" t | cut -f1,2 | tr '\t\n' '= ')
want='CONFIG_A=y CONFIG_B=y CONFIG_C=y CONFIG_D=m CONFIG_E=n CONFIG_F="hello world" CONFIG_G="a#b" CONFIG_H=123 CONFIG_I=-1 CONFIG_J=0x1F CONFIG_K=y '
[[ $got == "$want" ]] || fail "parse: $got"
misl_kernel_list_parse "$kl" t | sed -n 1p | grep -F "t ($kl:3)" >/dev/null || fail "origin"
ok "parse y/m/n/str/int/hex, comments, whitespace"

for bad in 'CONFIG_X=maybe' 'X=' 'CONFIG X' 'X="unterminated' 'X=1.5' '=y' 'X="a" junk'; do
  printf '# head\n%s\n' "$bad" >"$work/bad.list"
  refused "bad.list:2" misl_kernel_list_parse "$work/bad.list" t
done

# --- requests: nested overlays in apply order, later wins, conflict warns
MISL_ROOT=$work/root
export LFS=$work/lfs
ov=$MISL_ROOT/overlays
mkdir -p "$ov/terminal" "$ov/base/child" "$ov/other" "$LFS/var/lib/misl/overlays"
printf 'name=terminal\nstatus=alpha\ndefault=1\n' >"$ov/terminal/overlay.conf"
printf 'name=base\nstatus=alpha\nkernel=1\n' >"$ov/base/overlay.conf"
printf 'name=child\nstatus=alpha\n' >"$ov/base/child/overlay.conf"
printf 'name=other\nstatus=alpha\n' >"$ov/other/overlay.conf"
printf 'CONFIG_VIRTIO\nCONFIG_NET_X=m\nCONFIG_LOG_BUF_SHIFT=17\nCONFIG_SAME\n' >"$ov/base/kernel.list"
printf 'CONFIG_NET_X=y\nCONFIG_CMDLINE="console=ttyS0"\nSAME\n' >"$ov/base/child/kernel.list"
printf 'CONFIG_NEVER=y\n' >"$ov/other/kernel.list" # not applied
misl_overlay_apply base/child >/dev/null 2>&1
misl_overlay_kernel_wanted || fail "kernel wanted"
reqs=$(misl_kernel_list_requests 2>"$work/warn")
grep -F 'CONFIG_NET_X=m from base (' "$work/warn" | grep -F 'overridden by CONFIG_NET_X=y from base/child' >/dev/null || \
  fail "no conflict warning: $(cat "$work/warn")"
grep -F SAME "$work/warn" >/dev/null && fail "same value warned"
[[ $(grep -c . <<<"$reqs") == 5 ]] || fail "requests: $reqs"
grep -P '^CONFIG_NET_X\ty\tbase/child' <<<"$reqs" >/dev/null || fail "later overlay did not win"
grep -F NEVER <<<"$reqs" >/dev/null && fail "unapplied overlay read"
ok "requests: ancestors first, later wins, conflict warns"

# --- apply + verify
cfg=$work/.config
printf 'CONFIG_LOG_BUF_SHIFT=14\n# CONFIG_VIRTIO is not set\n' >"$cfg"
misl_kernel_list_apply sc <<<"$reqs"
misl_kernel_list_verify "$cfg" <<<"$reqs" || fail "verify after apply"
grep -qx 'CONFIG_CMDLINE="console=ttyS0"' "$cfg" || fail "set-str"
grep -qx 'CONFIG_LOG_BUF_SHIFT=17' "$cfg" || fail "set-val"
ok "apply via scripts/config flags; verify passes"

# full parse set through apply + verify (n absent or not set, hex case)
r2=$(misl_kernel_list_parse "$kl" t)
printf 'CONFIG_E=y\n' >"$cfg"
misl_kernel_list_apply sc <<<"$r2"
misl_kernel_list_verify "$cfg" <<<"$r2" || fail "verify full set"
sed -i '/CONFIG_E/d; s/^CONFIG_J=0x1F$/CONFIG_J=0x1f/' "$cfg"
misl_kernel_list_verify "$cfg" <<<"$r2" || fail "n absent / hex case"
ok "verify: =n absent counts as off, hex case-insensitive"

# --- verify failure: olddefconfig dropped options (missing deps)
sed -i '/^CONFIG_NET_X=/d; s/^CONFIG_CMDLINE=.*/CONFIG_CMDLINE=""/' "$cfg"
misl_kernel_list_apply sc <<<"$reqs"
sed -i 's/^CONFIG_NET_X=y/# CONFIG_NET_X is not set/; s/^CONFIG_LOG_BUF_SHIFT=.*/CONFIG_LOG_BUF_SHIFT=18/' "$cfg"
out=$( (misl_kernel_list_verify "$cfg" <<<"$reqs") 2>&1 ) && fail "verify did not fail"
[[ $out == *"CONFIG_NET_X wanted y, .config has # CONFIG_NET_X is not set (from base/child ("* ]] || fail "verify msg: $out"
[[ $out == *"CONFIG_LOG_BUF_SHIFT wanted 17, .config has CONFIG_LOG_BUF_SHIFT=18 (from base ("* ]] || fail "verify msg2: $out"
[[ $out == *"2 option(s) did not stick"* ]] || fail "verify count: $out"
ok "verify fails naming option, wanted, actual, overlay/file"
out=$(MISL_KERNEL_LIST_LAX=1 misl_kernel_list_verify "$cfg" <<<"$reqs" 2>&1) || fail "lax still failed"
[[ $out == *WARN*"CONFIG_NET_X wanted y"* ]] || fail "lax warn: $out"
ok "MISL_KERNEL_LIST_LAX=1 warns instead"

# malformed shipped file stops requests
printf 'CONFIG_OK\nCONFIG_BAD=q\n' >"$ov/base/child/kernel.list"
refused "base/child/kernel.list:2" misl_kernel_list_requests
misl_overlay_undo base/child base >/dev/null 2>&1

# --- shipped kernel.list files parse
MISL_ROOT=$REPO
while IFS= read -r f; do
  misl_kernel_list_parse "$f" "${f#"$REPO"/overlays/}" >/dev/null
done <<<"$(find "$REPO/overlays" -name kernel.list)"
ok "shipped kernel.list files parse"
printf 'kernel-list-smoke: all ok\n'
