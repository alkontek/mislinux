#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# Package groups (lib/groups.sh) against the real packages.manifest and
# overlays/, copied into /tmp with a fake snapshot and fake LFS. Pure
# parsing plus `sources stage` hardlinks of empty files. No root, no
# downloads, no builds.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/misl-groups-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
MISL_ROOT=$work/root
mkdir -p "$MISL_ROOT"
cp -a "$REPO/lib" "$REPO/config" "$REPO/overlays" "$MISL_ROOT/"
rm -f "$MISL_ROOT/config/misl.conf"
export MISL_ROOT
unset MISL_GROUPS MISL_TARGET_OVERLAYS MISL_SBCL_BOOTSTRAP_MD5 LFS
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
# shellcheck source=../../lib/docs.sh
. "$MISL_ROOT/lib/docs.sh"
# shellcheck source=../../lib/sources.sh
. "$MISL_ROOT/lib/sources.sh"
# shellcheck source=../../lib/overlay.sh
. "$MISL_ROOT/lib/overlay.sh"
# shellcheck source=../../lib/groups.sh
. "$MISL_ROOT/lib/groups.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }
man=$MISL_ROOT/config/packages.manifest
sel() { unset MISL_GROUPS_SEL; misl_groups_selected | paste -sd' ' -; }
want() { unset MISL_GROUPS_SEL; misl_group_tarball_wanted "$1"; }

# --- the real manifest: every row exactly one known group ---
known=$(misl_groups_known | paste -sd' ' -)
[[ $known == "base hw wifi bluetooth lisp cloud" ]] || fail "declared groups: '$known'"
misl_groups_check_manifest || fail "real manifest check"
rows=0
while IFS= read -r ln; do
  [[ -z $ln || $ln == \#* ]] && continue
  rows=$((rows + 1))
  n=$(grep -o 'group=[^ ]*' <<<"$ln" | wc -l)
  [[ $n -eq 1 ]] || fail "row has $n group= notes: $ln"
  g=$(grep -o 'group=[^ ]*' <<<"$ln"); g=${g#group=}
  [[ " $known " == *" $g "* ]] || fail "unknown group $g: $ln"
done <"$man"
[[ $rows -gt 100 ]] || fail "only $rows rows"
bad=$(awk '$1 ~ /^(0[567]|09|10)-/ && !/ group=base( |$)/' "$man")
[[ -z $bad ]] || fail "05/06/07/09/10 rows must be base: $bad"
for n in glib jinja2 markupsafe meson ninja python systemd dbus openssh htop; do
  awk -v n="$n" '$1=="08-system" && $2==n' "$man" | grep -E ' group=base( |$)' >/dev/null || fail "$n must be base"
done
for n in hwdata pciutils libusb usbutils ethtool alsa-lib alsa-ucm-conf alsa-utils lm-sensors; do
  awk -v n="$n" '$1=="08-system" && $2==n' "$man" | grep -E ' group=hw( |$)' >/dev/null || fail "$n not group=hw"
  [[ -f $REPO/stages/08-system/$n.sh ]] || fail "no recipe for $n"
done
for n in libnl wpa_supplicant wireless-regdb iw; do
  awk -v n="$n" '$1=="08-system" && $2==n' "$man" | grep -E ' group=wifi( |$)' >/dev/null || fail "$n not group=wifi"
done
awk '$1=="08-system" && $2=="bluez"' "$man" | grep -E ' group=bluetooth( |$)' >/dev/null || fail "bluez not group=bluetooth"
awk '$2=="sbcl"' "$man" | grep -E ' group=lisp( |$)' >/dev/null || fail "sbcl not group=lisp"
[[ -f $REPO/stages/08-system/sbcl.sh ]] || fail "no sbcl recipe"
while IFS= read -r q; do
  misl_overlay_load "$q"
  for g in ${OVERLAY_PACKAGES//,/ }; do
    [[ " $known " == *" $g "* ]] || fail "overlay $q packages=$g is not a declared group"
  done
done <<<"$(misl_overlay_all)"
ok "manifest: $rows rows, one known group each; overlay packages= known"

# --- bad manifests: file:line errors ---
badman() { # $1 label, $2 row, $3 expected substring
  local f=$work/bad-$1.manifest out
  { grep -v '^#' "$man" | head -3; printf '%s\n' "$2"; } >"$f"
  out=$(MISL_MANIFEST=$f bash -c '. "$MISL_ROOT/lib/common.sh"; . "$MISL_ROOT/lib/sources.sh"
    . "$MISL_ROOT/lib/overlay.sh"; . "$MISL_ROOT/lib/groups.sh"; misl_groups_check_manifest' 2>&1) \
    && fail "$1 manifest passed"
  [[ $out == *"$f:4:"* && $out == *"$3"* ]] || fail "$1: $out"
}
badman multi "08-system x 1 - - group=hw group=wifi" "more than one group"
badman comma "08-system x 1 - - group=hw,wifi" "more than one group"
badman missing "08-system x 1 - - implemented=0.4" "no group="
badman unknown "08-system x 1 - - group=nope" "unknown group"
ok "bad manifest: multi, comma, missing, unknown -> file:line"

# --- selection ---
[[ -z $(sel) ]] || fail "default (no LFS, terminal default) selected: $(sel)"
want glibc-2.44.tar.xz || fail "base tarball not wanted"
want glibc-fhs-1.patch || fail "base patch not wanted"
want not-in-manifest.tar.xz || fail "unlisted file must stay wanted"
! want bluez-5.87.tar.xz || fail "bluez wanted by default"
! want sbcl-2.6.10-source.tar.bz2 || fail "sbcl wanted by default"
ok "default: base only"

export MISL_TARGET_OVERLAYS=rog-strix-x570
[[ $(sel) == "bluetooth hw wifi" ]] || fail "rog: $(sel)"
[[ $(misl_groups_target_overlays | paste -sd' ' -) == "desktop/asus/rog-strix-x570 desktop" ]] || \
  fail "rog targets: $(misl_groups_target_overlays | paste -sd' ' -)"
want bluez-5.87.tar.xz || fail "rog: bluez not wanted"
want wpa_supplicant-2.12.tar.gz || fail "rog: wpa not wanted"
! want sbcl-2.6.10-source.tar.bz2 || fail "rog: sbcl wanted"
MISL_TARGET_OVERLAYS=desktop; [[ $(sel) == "bluetooth hw wifi" ]] || fail "desktop: $(sel)"
for t in cloud cloud/do cloud/aws cloud/gcp; do
  MISL_TARGET_OVERLAYS=$t; [[ $(sel) == cloud ]] || fail "$t: $(sel)"
  ! want wpa_supplicant-2.12.tar.gz || fail "$t: wpa wanted"
done
MISL_TARGET_OVERLAYS="do,terminal"; [[ $(sel) == cloud ]] || fail "do,terminal: $(sel)"
for t in terminal terminal/tui; do
  MISL_TARGET_OVERLAYS=$t; [[ -z $(sel) ]] || fail "$t: $(sel)"
  ! want wpa_supplicant-2.12.tar.gz || fail "$t: wpa wanted"
done
ok "targets: rog/desktop -> hw wifi bluetooth; cloud, do, aws, gcp -> cloud; terminal, tui -> base"

MISL_TARGET_OVERLAYS=rog-strix-x570 MISL_GROUPS=lisp; [[ $(sel) == "bluetooth hw lisp wifi" ]] || fail "rog+lisp: $(sel)"
MISL_TARGET_OVERLAYS=""; [[ $(sel) == lisp ]] || fail "lisp: $(sel)"
unset MISL_GROUPS_SEL
[[ $(misl_incoming_wanted | cut -f2) == sbcl-2.6.10-x86-64-linux-binary.tar.bz2 ]] || fail "incoming for lisp"
! want bluez-5.87.tar.xz || fail "lisp: bluez wanted"
MISL_GROUPS="hw, lisp"; [[ $(sel) == "hw lisp" ]] || fail "comma list: $(sel)"
MISL_GROUPS=all; [[ $(sel) == all ]] || fail "all: $(sel)"
want sbcl-2.6.10-source.tar.bz2 || fail "all: sbcl"
unset MISL_GROUPS_SEL
misl_group_notes_wanted "group=nosuch implemented=0.4" || fail "all: unknown group row"
MISL_GROUPS=""
unset MISL_GROUPS_SEL
[[ -z $(misl_incoming_wanted) ]] || fail "incoming without lisp"
misl_group_notes_wanted "group=base implemented=0.2" || fail "base row not wanted"
(misl_group_notes_wanted "implemented=0.2") 2>/dev/null && fail "row without group= accepted"
(misl_group_notes_wanted "group=hw,lisp") 2>/dev/null && fail "comma group accepted"
! misl_group_notes_wanted "group=hw implemented=0.4" || fail "hw row wanted with nothing selected"
[[ $(misl_group_label "group=hw x=1") == hw ]] || fail "label"
[[ $(misl_group_label "group=base implemented=0.2") == base ]] || fail "label base"
ok "MISL_GROUPS: lisp, comma lists, all, incoming only for lisp"

# --- applied overlay on a fake LFS ---
export LFS=$work/lfs
mkdir -p "$LFS/var/lib/misl/overlays/desktop"
touch "$LFS/var/lib/misl/overlays/desktop/applied"
[[ $(sel) == "bluetooth hw wifi" ]] || fail "applied desktop: $(sel)"
rm -rf "$LFS/var/lib/misl/overlays/desktop"
[[ -z $(sel) ]] || fail "after unapply: $(sel)"
ok "applied overlays on \$LFS count"

# --- sources stage on a fake snapshot ---
snap=$work/snap
export MISL_SNAPSHOT=$snap MISL_SOURCES=$snap/sources MISL_PATCHES=$snap/patches \
  MISL_DOCS_DIR=$snap/docs MISL_WGET_LIST=$snap/wget-list MISL_MD5SUMS=$snap/md5sums
mkdir -p "$MISL_SOURCES" "$MISL_PATCHES" "$snap/incoming"
M=https://example.invalid/m
for f in glibc-2.44.tar.xz bluez-5.87.tar.xz sbcl-2.6.10-source.tar.bz2 libnl-3.12.0.tar.gz; do
  : >"$MISL_SOURCES/$f"; printf '%s/sources/%s\n' "$M" "$f"
done >"$MISL_WGET_LIST"
: >"$MISL_PATCHES/glibc-fhs-1.patch"
printf '%s/patches/glibc-fhs-1.patch\n' "$M" >>"$MISL_WGET_LIST"
e=$(md5sum </dev/null | awk '{print $1}')
awk -v e="$e" '{n=$0; sub(/^.*\//,"",n); d=($0 ~ /patches/)?"patches":"sources"; print e"  "d"/"n}' \
  "$MISL_WGET_LIST" >"$MISL_MD5SUMS"
: >"$snap/incoming/sbcl-2.6.10-x86-64-linux-binary.tar.bz2"
mkdir -p "$LFS"
out=$(MISL_TARGET_OVERLAYS=rog-strix-x570 misl_sources_check 2>&1) || fail "check rog: $out"
[[ $out == *"GROUP-SKIP sbcl-2.6.10-source.tar.bz2"* && $out == *"OK bluez-5.87.tar.xz"* ]] || fail "check rog output: $out"
MISL_TARGET_OVERLAYS=rog-strix-x570 misl_sources_stage >/dev/null 2>&1 || fail "stage rog"
S=$LFS/usr/src/misl/SOURCES
for f in glibc-2.44.tar.xz bluez-5.87.tar.xz libnl-3.12.0.tar.gz glibc-fhs-1.patch; do
  [[ -f $S/$f ]] || fail "rog: $f not staged"
done
[[ ! -e $S/sbcl-2.6.10-source.tar.bz2 && ! -e $S/sbcl-2.6.10-x86-64-linux-binary.tar.bz2 ]] || fail "rog staged sbcl"
[[ $(cat "$LFS/var/lib/misl/groups") == "bluetooth hw wifi" ]] || fail "record: $(cat "$LFS/var/lib/misl/groups")"
[[ $(sel) == "bluetooth hw wifi" ]] || fail "recorded selection not used: $(sel)"
MISL_GROUPS=lisp MISL_SBCL_BOOTSTRAP_MD5=$e misl_sources_stage >/dev/null 2>&1 || fail "stage lisp"
[[ -f $S/sbcl-2.6.10-source.tar.bz2 && -f $S/sbcl-2.6.10-x86-64-linux-binary.tar.bz2 ]] || fail "lisp: sbcl not staged"
[[ $(awk '{print $1}' "$S/sbcl-2.6.10-x86-64-linux-binary.tar.bz2.md5") == "$e" ]] || fail "sbcl md5 sidecar"
out=$(MISL_GROUPS=lisp MISL_SBCL_BOOTSTRAP_MD5=$e misl_sources_check 2>&1) || fail "check lisp: $out"
[[ $out == *"OK incoming sbcl-2.6.10-x86-64-linux-binary.tar.bz2"* ]] || fail "env md5: $out"
out=$(MISL_GROUPS=lisp misl_sources_check 2>&1) && fail "fake sbcl passed the manifest md5"
[[ $out == *"HASH-MISMATCH incoming sbcl"* ]] || fail "manifest md5: $out"
out=$(MISL_GROUPS=lisp MISL_SBCL_BOOTSTRAP_MD5=0123 misl_sources_check 2>&1) && fail "bad md5 passed"
[[ $out == *"HASH-MISMATCH incoming"* ]] || fail "mismatch: $out"
ok "sources check/stage: group skip, incoming sbcl + md5 sidecar, recorded selection"

out=$(MISL_GROUPS=lisp misl_groups_list)
[[ $out == *"selected: base lisp"* && $out == *"base (always) - "* && $out == *"lisp (yes) - "* \
   && $out == *"hw (no) - "* && $out == *"wifi (no) - "* && $out == *"bluetooth (no) - "* && $out == *"  libnl wpa_supplicant wireless-regdb iw"* ]] \
   || fail "groups list: $out"
ok "misl groups listing"
printf 'package-groups smoke: all ok\n'
