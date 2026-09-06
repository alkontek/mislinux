# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Nothing extra: misl overlay undo already removed every path recorded
# by apply.sh (files/, plus the timers.target.wants/fstrim.timer link
# made at apply time and its wants dir if apply.sh created it). A link
# that existed before apply was never recorded and is left alone.
:
