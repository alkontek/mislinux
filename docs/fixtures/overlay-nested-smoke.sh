#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# Nested overlays on a fake overlays/ tree and a fake LFS under /tmp.
# Does not touch the real overlays/ or any real LFS. No root needed.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MISL_ROOT=$REPO
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$REPO/lib/common.sh"
# shellcheck source=../../lib/overlay.sh
. "$REPO/lib/overlay.sh"

work=$(mktemp -d /tmp/misl-overlay-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
MISL_ROOT=$work/root
export LFS=$work/lfs
ov=$MISL_ROOT/overlays

conf() { # qname status [extra lines...]
  local q=$1 st=$2
  shift 2
  mkdir -p "$ov/$q"
  {
    printf 'name=%s\ntitle=%s\nclass=local\nstatus=%s\n' "${q##*/}" "$q" "$st"
    printf '%s\n' "$@"
  } >"$ov/$q/overlay.conf"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }
# Expect a failure (die) with a message matching $1.
refused() {
  local pat=$1 out
  shift
  if out=$( ("$@") 2>&1 ); then
    fail "not refused: $*"
  fi
  [[ $out == *"$pat"* ]] || fail "refused for the wrong reason: $* -> $out"
  ok "refused: $* ($pat)"
}

conf terminal alpha default=1 priority=10
conf top alpha priority=40
conf top/mid alpha parent=top priority=41
conf top/mid/grp/leaf alpha parent=top/mid priority=42 # grp/ is grouping
conf top/old alpha priority=43
conf stubby stub priority=50
conf stubby/kid alpha priority=51
conf a/dup alpha priority=60
conf b/dup alpha priority=61
mkdir -p "$ov/a" "$ov/b" # pure grouping dirs at the top level
cat >"$ov/top/mid/apply.sh" <<'H'
# shellcheck shell=bash
mkdir -p "$LFS/etc"
printf 'mid\n' >"$LFS/etc/mid.conf"
misl_overlay_own "$LFS/etc/mid.conf"
H

mkdir -p "$LFS/etc" "$LFS/usr/lib" "$LFS/var/lib/misl/overlays"
printf 'NAME="MIS Linux"\nMISL_OVERLAYS="terminal"\n' >"$LFS/usr/lib/os-release"
snap() { (cd "$LFS" && find . -printf '%M %s %p\n' | LC_ALL=C sort && find . -type f -exec md5sum {} + | LC_ALL=C sort); }
before=$(snap)

# discovery
all=$(misl_overlay_all | tr '\n' ' ')
[[ $all == *"top/mid/grp/leaf "* ]] || fail "leaf not discovered: $all"
[[ $all != *"top/mid/grp "* && $all != *" a "* ]] || fail "grouping dir listed: $all"
[[ $(misl_overlay_parent_of top/mid/grp/leaf) == top/mid ]] || fail "parent of leaf"
[[ $(misl_overlay_ancestors top/mid/grp/leaf | tr '\n' ' ') == "top top/mid " ]] || fail "ancestors"
[[ $(misl_overlay_canon leaf) == top/mid/grp/leaf ]] || fail "short name"
ok "discovery, parents, short names"
refused ambiguous misl_overlay_canon dup
refused "no overlay" misl_overlay_canon nope
misl_overlay_list >/dev/null

# apply the 3-level child: pulls top, top/mid first
order=$(misl_overlay_resolve leaf | tr '\n' ' ')
[[ $order == "top top/mid top/mid/grp/leaf " ]] || fail "resolve order: $order"
misl_overlay_apply leaf >/dev/null 2>&1
st=$LFS/var/lib/misl/overlays
for q in top top/mid top/mid/grp/leaf; do
  [[ -f $st/$q/applied ]] || fail "no stamp $q"
done
grep -qx 'name=top/mid/grp/leaf' "$st/top/mid/grp/leaf/applied" || fail "stamp name"
[[ -f $LFS/etc/mid.conf ]] || fail "hook did not run"
grep -qx 'MISL_OVERLAYS="terminal top top/mid top/mid/grp/leaf"' "$LFS/usr/lib/os-release" || \
  fail "os-release: $(grep MISL_OVERLAYS "$LFS/usr/lib/os-release")"
[[ $(misl_overlay_active_qnames | tr '\n' ' ') == "terminal top top/mid top/mid/grp/leaf " ]] || fail "active qnames"
misl_overlay_list --no-header | grep -E '^top/mid/grp/leaf +alpha +on' >/dev/null || fail "list on"
ok "apply leaf pulls ancestors; stamps, MISL_OVERLAYS"

refused "undo children first" misl_overlay_undo top
refused "undo children first" misl_overlay_undo top/mid
refused "the default" misl_overlay_undo terminal
refused "stubby is stub" misl_overlay_apply stubby/kid
refused "is stub" misl_overlay_apply stubby
refused ambiguous misl_overlay_apply dup

misl_overlay_undo leaf top/mid top >/dev/null 2>&1
[[ ! -e $LFS/etc/mid.conf ]] || fail "owned file left behind"
[[ $(snap) == "$before" ]] || { diff <(printf '%s\n' "$before") <(snap) || true; fail "tree differs after apply+undo"; }
ok "apply + undo leaves the fake LFS byte-identical"

# 0.3 flat stamp: <state>/old/applied counts as top/old
mkdir -p "$st/old"
printf 'name=old\n' >"$st/old/applied"
misl_overlay_applied top/old || fail "legacy stamp not seen"
misl_overlay_applied old || fail "legacy stamp via short name"
misl_overlay_status | grep 'top/old .*0.3 stamp' >/dev/null || fail "status legacy"
grep -q 'top/old' <<<"$(misl_overlay_active_qnames)" || fail "legacy not active"
misl_overlay_undo old >/dev/null 2>&1
[[ ! -e $st/old && ! -e $st/top/old ]] || fail "legacy undo left state"
mkdir -p "$st/old"
printf 'name=old\n' >"$st/old/applied"
misl_overlay_apply top >/dev/null 2>&1
misl_overlay_apply_one top/old >/dev/null 2>&1
[[ -f $st/top/old/applied && ! -e $st/old ]] || fail "legacy stamp not migrated"
refused "undo children first" misl_overlay_undo top
misl_overlay_undo top/old top >/dev/null 2>&1
[[ $(snap) == "$before" ]] || fail "tree differs after legacy round trip"
ok "0.3 flat stamps: seen, migrated, undone"

# parent= must match the folder
conf top/mid/grp/leaf alpha parent=top
refused "folder implies top/mid" misl_overlay_load leaf
conf top/mid/grp/leaf alpha parent=mid
misl_overlay_load leaf # leaf of the implied parent is fine
[[ $OVERLAY_PARENT == top/mid ]] || fail "OVERLAY_PARENT"
conf top/mid/grp/leaf alpha name=other
refused "but the folder is leaf" misl_overlay_load top/mid/grp/leaf
ok "parent=/name= validated"

# real tree: shipped names and parents
MISL_ROOT=$REPO
[[ $(misl_overlay_canon do) == cloud/do ]] || fail "do -> cloud/do"
[[ $(misl_overlay_parent_of desktop/asus/rog-strix-x570) == desktop ]] || fail "rog parent"
[[ $(misl_overlay_resolve rog-strix-x570 | tr '\n' ' ') == "desktop desktop/asus/rog-strix-x570 " ]] \
  || fail "rog resolves to desktop + rog"
for q in $(misl_overlay_all); do misl_overlay_load "$q"; done
ok "shipped overlays load; rog-strix-x570 parent is desktop, resolves with it"
printf 'overlay-nested-smoke: all ok\n'
