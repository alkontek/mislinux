# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Host apply for the cloud overlay. Implementation stays in lib/cloud.sh.

if [[ ${MISL_FETCH:-1} == 1 ]]; then
  misl_cloud_fetch 0
fi
misl_overlay_cloud_apply
