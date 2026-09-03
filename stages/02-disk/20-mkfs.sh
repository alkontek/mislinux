# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# 0.2 does not format disks. See docs/disk-safety.md.
misl_disk_plan
die "mkfs is operator-run in 0.2 (policy A)"
