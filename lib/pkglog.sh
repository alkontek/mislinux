# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash

# A row is "ready" only when stages/<stage> holds a non-stub recipe.
misl_status_has_recipe() {
  local stage=$1 name=$2 f
  if declare -F misl_recipe_in_stage >/dev/null; then
    f=$(misl_recipe_in_stage "$stage" "$name") || return 1
  else
    f=$MISL_ROOT/stages/$stage/${name}.sh
    [[ -f $f ]] || return 1
  fi
  ! grep -q 'not implemented' "$f"
}

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
    elif [[ -n ${LFS:-} && -f $LFS/var/lib/misl/integrated/$name ]]; then
      state=integrated
    elif [[ $notes == *blocked=* ]]; then
      state=blocked
    elif [[ $notes == *implemented=* ]] && misl_status_has_recipe "$stage" "$name"; then
      state=ready
    elif [[ $notes == *implemented=* ]]; then
      state=norecipe
    else
      state=stub
    fi
    printf '%-16s %-22s %-10s %s\n' "$stage" "$name" "$ver" "$state"
  done < "$man"
}
