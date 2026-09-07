# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash

# See docs/disk-safety.md.
require_lfs_set
[[ -n ${MISL_DISK:-} ]] || die "MISL_DISK is not set"
die "mount is operator-run: policy A don't create for format disks"
