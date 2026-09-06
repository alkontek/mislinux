#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# config/incoming.manifest (lib/groups.sh, lib/cloud.sh): parse the real
# manifest, group selection, md5 check and staging against fake files in
# /tmp (wheels under incoming/wheels/), the missing-wheel error. No root, no network, no builds.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/misl-incoming-smoke.XXXXXX)
trap 'rm -rf "$work"' EXIT
MISL_ROOT=$work/root
mkdir -p "$MISL_ROOT"
cp -a "$REPO/lib" "$REPO/config" "$REPO/overlays" "$MISL_ROOT/"
rm -f "$MISL_ROOT/config/misl.conf"
export MISL_ROOT
unset MISL_GROUPS MISL_TARGET_OVERLAYS MISL_SBCL_BOOTSTRAP_MD5 MISL_CLOUD_INIT_MD5 LFS MISL_MD5SUMS
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
# shellcheck source=../../lib/sources.sh
. "$MISL_ROOT/lib/sources.sh"
# shellcheck source=../../lib/overlay.sh
. "$MISL_ROOT/lib/overlay.sh"
# shellcheck source=../../lib/groups.sh
. "$MISL_ROOT/lib/groups.sh"
# shellcheck source=../../lib/cloud.sh
. "$MISL_ROOT/lib/cloud.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }
man=$MISL_ROOT/config/incoming.manifest
rows() { unset MISL_GROUPS_SEL; misl_incoming_wanted "$@"; }

# --- the real manifest ---
n=$(rows cloud | wc -l)
w=$(rows cloud | awk -F'\t' '$5 == "wheel"' | wc -l)
(( n == 14 && w == 13 )) || fail "cloud rows=$n wheels=$w"
rows cloud | awk -F'\t' '$5 == "wheel" && $3 !~ /^[0-9a-f]{32}$/ { exit 1 }' || fail "wheel without md5"
rows cloud | awk -F'\t' '$5 == "wheel" && $2 !~ /^wheels\/[^\/]+(-(py3|py2\.py3)-none-any|-cp314-cp314-manylinux.*x86_64)\.whl$/ { exit 1 }' \
  || fail "wheel not wheels/<name>.whl with py3-none-any or cp314 manylinux x86_64"
[[ $(rows cloud | awk -F'\t' '$5 == "tarball" { print $2 }') == cloud-init-26.2.tar.gz ]] || fail "cloud-init row"
[[ $(rows lisp | cut -f2,3) == "sbcl-2.6.10-x86-64-linux-binary.tar.bz2"$'\t'501733c5aa52abc4bf468e308c3daff4 ]] || fail "sbcl row"
! grep -qiE 'jinja2|markupsafe|rpds' "$man" || fail "base or rust package in incoming"
grep -q 'jsonschema-4\.17\.' "$man" || fail "jsonschema not <4.18"
[[ $(misl_cloud_wheel_files | wc -l) -eq 13 ]] || fail "misl_cloud_wheel_files"
ok "manifest: 13 pinned wheels + cloud-init + sbcl, md5s, tags"

# --- group selection ---
[[ -z $(rows) ]] || fail "nothing selected: $(rows | cut -f2)"
[[ $(MISL_TARGET_OVERLAYS=cloud/do rows | cut -f1 | sort -u) == cloud ]] || fail "cloud/do target"
[[ $(MISL_TARGET_OVERLAYS=terminal rows | wc -l) -eq 0 ]] || fail "terminal target"
[[ $(MISL_GROUPS=lisp rows | cut -f1 | sort -u) == lisp ]] || fail "lisp"
[[ $(MISL_GROUPS=all rows | wc -l) -eq 15 ]] || fail "all"
export LFS=$work/lfs
mkdir -p "$LFS/var/lib/misl/overlays/cloud"
touch "$LFS/var/lib/misl/overlays/cloud/applied"
[[ $(rows | wc -l) -eq 14 ]] || fail "applied cloud"
rm -rf "$LFS/var/lib/misl/overlays/cloud"
ok "selection: cloud overlays -> cloud rows; lisp; all; applied cloud"

# --- bad rows ---
bad=$work/bad.manifest
printf 'nosuch x 1 x.whl - kind=wheel\n' >"$bad"
(MISL_INCOMING_MANIFEST=$bad MISL_GROUPS=all misl_incoming_wanted) 2>/dev/null && fail "unknown group accepted"
printf 'cloud x 1\n' >"$bad"
(MISL_INCOMING_MANIFEST=$bad misl_incoming_wanted cloud) 2>/dev/null && fail "short row accepted"
printf 'cloud x 1 ../x.whl - kind=wheel\n' >"$bad"
(MISL_INCOMING_MANIFEST=$bad misl_incoming_wanted cloud) 2>/dev/null && fail "path outside incoming/ accepted"
ok "unknown group, short rows and paths outside incoming/ rejected"

# --- md5 check and stage against fake files ---
MISL_SNAPSHOT=$work/snap
MISL_SOURCES=$MISL_SNAPSHOT/sources
export MISL_SNAPSHOT MISL_SOURCES
fake=$work/fake.manifest
mkdir -p "$MISL_SNAPSHOT/incoming/wheels"
printf 'a\n' >"$MISL_SNAPSHOT/incoming/wheels/a-1-py3-none-any.whl"
printf 'b\n' >"$MISL_SNAPSHOT/incoming/b-1.tar.gz"
ma=$(md5sum "$MISL_SNAPSHOT/incoming/wheels/a-1-py3-none-any.whl" | awk '{print $1}')
mb=$(md5sum "$MISL_SNAPSHOT/incoming/b-1.tar.gz" | awk '{print $1}')
{
  printf 'cloud a 1 wheels/a-1-py3-none-any.whl %s kind=wheel\n' "$ma"
  printf 'cloud b 1 b-1.tar.gz - kind=tarball md5env=MISL_FAKE_B_MD5\n'
} >"$fake"
export MISL_INCOMING_MANIFEST=$fake
out=$(misl_incoming_check cloud 2>&1) || fail "check: $out"
[[ $out == *"OK incoming wheels/a-1-py3-none-any.whl"* && $out == *"NO-HASH incoming b-1.tar.gz"*"MISL_FAKE_B_MD5"* ]] || fail "check out: $out"
out=$(MISL_FAKE_B_MD5=$mb misl_incoming_check cloud 2>&1) || fail "env md5: $out"
[[ $out == *"OK incoming b-1.tar.gz"* ]] || fail "env md5 out: $out"
out=$(MISL_FAKE_B_MD5=0123 misl_incoming_check cloud 2>&1) && fail "bad env md5 passed"
[[ $out == *"HASH-MISMATCH incoming b-1.tar.gz"* ]] || fail "mismatch out: $out"
printf 'x\n' >>"$MISL_SNAPSHOT/incoming/wheels/a-1-py3-none-any.whl"
(misl_incoming_stage "$work/S" cloud) >/dev/null 2>&1 && fail "stage of a bad md5 passed"
printf 'a\n' >"$MISL_SNAPSHOT/incoming/wheels/a-1-py3-none-any.whl"
misl_incoming_stage "$work/S" cloud >/dev/null 2>&1 || fail "stage"
[[ -f $work/S/wheels/a-1-py3-none-any.whl && $(cat "$work/S/wheels/a-1-py3-none-any.whl.md5") == "$ma  a-1-py3-none-any.whl" ]] || fail "staged wheels/a + md5"
MISL_MD5SUMS=$work/md5sums; export MISL_MD5SUMS
printf '%s  incoming/wheels/a-1-py3-none-any.whl\n' 0123 >"$MISL_MD5SUMS"
(misl_incoming_check cloud) >/dev/null 2>&1 && fail "md5sums entry not used"
unset MISL_MD5SUMS
[[ -f $work/S/b-1.tar.gz && ! -e $work/S/b-1.tar.gz.md5 ]] || fail "staged b without md5"
rm "$MISL_SNAPSHOT/incoming/b-1.tar.gz"
out=$(misl_incoming_check cloud 2>&1) && fail "missing passed"
[[ $out == *"MISSING incoming (cloud) b-1.tar.gz"* ]] || fail "missing out: $out"
ok "md5: manifest, md5env, mismatch, missing; stage refuses a bad md5"

# --- install: missing wheel names the file; no pip reached ---
unset MISL_INCOMING_MANIFEST
mkdir -p "$work/src/wheels"
out=$(MISL_CLOUD_SOURCES=$work/src misl_cloud_pip_deps 2>&1) && fail "pip deps without wheels passed"
[[ $out == *"cloud-init wheels missing in $work/src/wheels: "*"pyyaml-6.0.3-cp314"*"urllib3-2.8.0-py3-none-any.whl"*"./misl cloud fetch"* ]] || fail "missing msg: $out"
! grep -rqiE 'pip3? download|pypi\.org' "$REPO/lib" "$REPO/misl" "$REPO/overlays" "$REPO/stages" || fail "pip download / PyPI in the tree"
ok "missing wheels named; no pip download or PyPI in lib/misl/overlays/stages"

printf 'incoming-smoke: all ok\n'
