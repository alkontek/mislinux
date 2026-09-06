# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Installs files/ into $LFS; every path is recorded in the owned list.
misl_overlay_install_files

# Enable fstrim.timer (weekly TRIM) on the target. The repo holds no
# symlinks: the wants link is made here and recorded in the owned list,
# so `misl overlay undo desktop` removes exactly that link (and the
# wants dir only if this overlay created it and it is empty).
misl_desktop_enable_fstrim() {
  local root wants link p target=/usr/lib/systemd/system/fstrim.timer
  root=$(misl_overlay_dest)
  wants=$root/etc/systemd/system/timers.target.wants
  link=$wants/fstrim.timer
  if [[ -e $link || -L $link ]]; then
    info "fstrim.timer already enabled on the target; not taking it"
    return 0
  fi
  local d=$root
  for p in etc etc/systemd etc/systemd/system etc/systemd/system/timers.target.wants; do
    d=$root/$p
    [[ -d $d ]] || { mkdir -m755 "$d" && misl_overlay_own "$d/"; }
  done
  if [[ -f $root$target ]] && command -v systemctl >/dev/null 2>&1 &&
    systemctl --root="${root:-/}" enable fstrim.timer >/dev/null 2>&1 && [[ -L $link ]]; then
    :
  else
    rm -f "$link"
    ln -s "$target" "$link"
  fi
  misl_overlay_own "$link"
  info "enabled fstrim.timer ($link -> $(readlink "$link"))"
}
misl_desktop_enable_fstrim
