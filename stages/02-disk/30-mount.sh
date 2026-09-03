# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# 0.2 does not mount the target disk. See docs/disk-safety.md.
require_lfs_set
[[ -n ${MISL_DISK:-} ]] || die "MISL_DISK is not set"
die "mount is operator-run in 0.2: mkdir -p \$LFS && mount <root-part> \$LFS"
