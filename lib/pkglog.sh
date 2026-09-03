# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash

misl_status() {
  local man=$MISL_ROOT/config/packages.manifest
  local stage name ver tarball patches notes pass state stamp
  printf '%-16s %-22s %-10s %s\n' STAGE NAME VERSION STATE
  while read -r stage name ver tarball patches notes; do
    [[ $stage == \#* || -z $stage ]] && continue
    pass=1
    if [[ $notes == *pass=* ]]; then
      pass=${notes##*pass=}
      pass=${pass%% *}
      pass=${pass%%,*}
    fi
    stamp=
    [[ -n ${LFS:-} ]] && stamp=$LFS/var/lib/misl/stamps/${stage}-${name}-${pass}.done
    if [[ -n $stamp && -f $stamp ]]; then
      state=done
    elif [[ $notes == *implemented=0.2* ]]; then
      state=ready
    else
      state=stub
    fi
    printf '%-16s %-22s %-10s %s\n' "$stage" "$name" "$ver" "$state"
  done < "$man"
}
