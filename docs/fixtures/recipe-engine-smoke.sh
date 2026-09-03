#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# Dummy-tarball walk through recipe_main. Does not touch misl-1.0-systemd/.
set -euo pipefail
MISL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export MISL_ROOT
# shellcheck source=../../lib/common.sh
. "$MISL_ROOT/lib/common.sh"
. "$MISL_ROOT/lib/config.sh"
misl_load_config
. "$MISL_ROOT/lib/sources.sh"
. "$MISL_ROOT/lib/recipe.sh"

work=$(mktemp -d /tmp/misl-recipe-smoke.XXXXXX)
export LFS=$work/lfs
mkdir -p "$LFS/usr/src/misl/SOURCES" "$LFS/tools" "$LFS/var/lib/misl"/{stamps,logs,pkglog}

src=$work/dummy-pkg-0.0
mkdir -p "$src"
printf 'dummy\n' > "$src/README"
tar -C "$work" -cf "$LFS/usr/src/misl/SOURCES/dummy-pkg-0.0.tar" dummy-pkg-0.0

pkg_name=dummy-pkg
pkg_version=0.0
pkg_tarball=dummy-pkg-0.0.tar
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_configure() { :; }
pkg_build() { :; }
pkg_install() { mkdir -p "$LFS/tools"; printf 'ok\n' > "$LFS/tools/dummy-pkg"; }

recipe_main

[[ -f $LFS/var/lib/misl/stamps/08-system-dummy-pkg-1.done ]] || die "missing stamp"
[[ -f $LFS/var/lib/misl/pkglog/packages.tsv ]] || die "missing pkglog"
[[ -f $LFS/tools/dummy-pkg ]] || die "missing install product"
info "recipe-engine-smoke OK ($work)"
rm -rf "$work"
