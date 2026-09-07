# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd §10.3 Linux-7.1.8
pkg_name=linux
pkg_version=7.1.8
pkg_tarball=linux-7.1.8.tar.xz
pkg_patches=
pkg_stage=10-boot
pkg_pass=1
pkg_builddir=in-tree

pkg_pre_configure() {
  local t dest
  for t in flex bison bc perl gcc make; do
    command -v "$t" >/dev/null 2>&1 || die "kernel needs $t (./misl build $t)"
  done
  [[ -f /usr/include/gelf.h ]] || die "kernel needs libelf headers (./misl build libelf)"
  if [[ ${MISL_FORCE:-0} == 1 ]]; then
    dest=$(misl_dest)
    rm -rf "${dest}/lib/modules/7.1.8" "${dest}/lib/modules/7.1.8-misl"
  fi
}

# tarball ships scripts/config mode 644; invoking it without sh skips
# every --enable and you get a defconfig kernel (no squashfs).
_misl_linux_sc() {
  sh scripts/config --file .config "$@"
}

_misl_linux_overlay_kernel() {
  if declare -F misl_overlay_kernel_wanted >/dev/null 2>&1; then
    misl_overlay_kernel_wanted
    return $?
  fi
  [[ ${MISL_CLOUD:-0} == 1 ]] && return 0
  local root=/var/lib/misl
  if [[ -n ${LFS:-} && ${LFS} != / ]]; then
    root=${LFS%/}/var/lib/misl
  fi
  [[ -f $root/overlays/cloud/applied ]]
}

pkg_configure() {
  unset KBUILD_OUTPUT O
  export KCONFIG_CONFIG="$PWD/.config"
  make mrproper
  make defconfig
  [[ -f scripts/config ]] || die "kernel tree has no scripts/config"

  _misl_linux_sc --set-str CONFIG_LOCALVERSION "-misl"

  _misl_linux_sc --enable CONFIG_IKCONFIG
  _misl_linux_sc --enable CONFIG_IKCONFIG_PROC
  _misl_linux_sc --enable CONFIG_CGROUPS
  _misl_linux_sc --enable CONFIG_MEMCG
  _misl_linux_sc --enable CONFIG_CGROUP_SCHED
  _misl_linux_sc --enable CONFIG_FAIR_GROUP_SCHED
  _misl_linux_sc --disable CONFIG_RT_GROUP_SCHED
  _misl_linux_sc --enable CONFIG_INET
  _misl_linux_sc --enable CONFIG_IPV6
  _misl_linux_sc --enable CONFIG_EFI
  _misl_linux_sc --enable CONFIG_EFI_STUB
  _misl_linux_sc --enable CONFIG_FB
  _misl_linux_sc --enable CONFIG_FRAMEBUFFER_CONSOLE
  _misl_linux_sc --enable CONFIG_EXT4_FS
  _misl_linux_sc --enable CONFIG_VFAT_FS
  _misl_linux_sc --enable CONFIG_NLS_ISO8859_1
  _misl_linux_sc --enable CONFIG_DEVTMPFS
  _misl_linux_sc --enable CONFIG_DEVTMPFS_MOUNT
  _misl_linux_sc --enable CONFIG_INOTIFY_USER
  _misl_linux_sc --enable CONFIG_TMPFS
  _misl_linux_sc --enable CONFIG_TMPFS_POSIX_ACL
  _misl_linux_sc --enable CONFIG_AUTOFS_FS
  _misl_linux_sc --enable CONFIG_NET
  _misl_linux_sc --enable CONFIG_PACKET
  _misl_linux_sc --enable CONFIG_UNIX
  _misl_linux_sc --enable CONFIG_SYSVIPC
  _misl_linux_sc --enable CONFIG_SIGNALFD
  _misl_linux_sc --enable CONFIG_TIMERFD
  _misl_linux_sc --enable CONFIG_EPOLL
  _misl_linux_sc --enable CONFIG_FHANDLE
  _misl_linux_sc --enable CONFIG_SECCOMP

  # Live ISO/USB. SQUASHFS sits under MISC_FILESYSTEMS.
  _misl_linux_sc --enable CONFIG_FB_EFI
  _misl_linux_sc --enable CONFIG_FB_SIMPLE
  _misl_linux_sc --enable CONFIG_SYSFB_SIMPLEFB
  _misl_linux_sc --enable CONFIG_DRM
  _misl_linux_sc --enable CONFIG_DRM_FBDEV_EMULATION
  _misl_linux_sc --enable CONFIG_DRM_SIMPLEDRM
  _misl_linux_sc --enable CONFIG_BLOCK
  _misl_linux_sc --enable CONFIG_MISC_FILESYSTEMS
  _misl_linux_sc --enable CONFIG_SQUASHFS
  _misl_linux_sc --enable CONFIG_SQUASHFS_ZLIB
  _misl_linux_sc --enable CONFIG_OVERLAY_FS
  _misl_linux_sc --enable CONFIG_ISO9660_FS
  _misl_linux_sc --enable CONFIG_BLK_DEV_LOOP
  _misl_linux_sc --enable CONFIG_BLK_DEV_SR
  _misl_linux_sc --enable CONFIG_ATA
  _misl_linux_sc --enable CONFIG_VIRTIO_SCSI

  make olddefconfig

  # Cloud VPS: virtio + 8250 from overlays/cloud/kernel.list
  if _misl_linux_overlay_kernel; then
    local cfg klist n root
    if [[ ${LFS:-} == / || -z ${LFS:-} ]]; then
      root=/var/lib/misl
    else
      root=${LFS%/}/var/lib/misl
    fi
    # No < <() — chroot often has no /dev/fd (line used to die: /dev/fd/63).
    for klist in "${MISL_ROOT:-.}"/overlays/*/kernel.list; do
      [[ -f $klist ]] || continue
      n=$(basename "$(dirname "$klist")")
      [[ -f $root/overlays/$n/applied ]] || continue
      while IFS= read -r cfg || [[ -n $cfg ]]; do
        [[ $cfg =~ ^CONFIG_ ]] || continue
        _misl_linux_sc --enable "$cfg"
      done <"$klist"
    done
    make olddefconfig
  fi

  grep -q '^CONFIG_SQUASHFS=y' .config || \
    die "CONFIG_SQUASHFS is not y after olddefconfig ($(grep SQUASHFS .config | head -3))"
}

pkg_build() {
  export KCONFIG_CONFIG="${KCONFIG_CONFIG:-$PWD/.config}"
  make ${MISL_MAKEFLAGS:-}
}

pkg_install() {
  local dest kver
  dest=$(misl_dest)
  kver=7.1.8-misl
  make INSTALL_MOD_PATH="${dest:-/}" modules_install
  mkdir -pv "${dest}/boot"
  if [[ -f arch/x86/boot/bzImage ]]; then
    cp -v arch/x86/boot/bzImage "${dest}/boot/vmlinuz-${kver}"
  elif [[ -f arch/x86_64/boot/bzImage ]]; then
    cp -v arch/x86_64/boot/bzImage "${dest}/boot/vmlinuz-${kver}"
  else
    die "no bzImage"
  fi
  cp -v System.map "${dest}/boot/System.map-${kver}"
  cp -v .config "${dest}/boot/config-${kver}"
  ln -sfv "vmlinuz-${kver}" "${dest}/boot/vmlinuz"
  grep -q '^CONFIG_SQUASHFS=y' "${dest}/boot/config-${kver}" || \
    die "installed ${dest}/boot/config-${kver} has no CONFIG_SQUASHFS=y"
}
