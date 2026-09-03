#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# Download LFS URLs from wget-list.original into misl-1.0-systemd/sources.original.
# Operator tool. Does not run unless MISL_FETCH=1.

set -euo pipefail

MISL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SNAP=$(cd "$MISL_ROOT/../misl-1.0-systemd" && pwd)
LIST=${MISL_WGET_LIST_ORIGINAL:-$SNAP/wget-list.original}
DEST=${MISL_SOURCES_ORIGINAL:-$SNAP/sources.original}

if [[ ${MISL_FETCH:-0} != 1 ]]; then
  echo "fetch disabled (set MISL_FETCH=1); agent sessions must leave this off" >&2
  exit 2
fi

[[ -f $LIST ]] || { echo "missing $LIST" >&2; exit 2; }
[[ $(basename "$LIST") == wget-list.original ]] || {
  echo "refusing $LIST — this script only reads wget-list.original" >&2
  exit 2
}

command -v wget >/dev/null 2>&1 || { echo "wget not found" >&2; exit 2; }

mkdir -p "$DEST"

# LFS-style bulk fetch. Continue partial files. Do not touch sources/ or patches/.
wget --input-file="$LIST" --continue --directory-prefix="$DEST" --no-clobber

echo "fetched into $DEST from $LIST"
echo "next: copy tarballs to $SNAP/sources and patches to $SNAP/patches, then misl sources check"
