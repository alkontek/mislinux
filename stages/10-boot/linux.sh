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
  local t
  for t in flex bison bc perl gcc make; do
    command -v "$t" >/dev/null 2>&1 || die "kernel needs $t (./misl build $t)"
  done
  [[ -f /usr/include/gelf.h ]] || die "kernel needs libelf headers (./misl build libelf)"
}

pkg_configure() {
  make mrproper
  make defconfig
  if [[ -x scripts/config ]]; then
    scripts/config --enable CONFIG_IKCONFIG
    scripts/config --enable CONFIG_IKCONFIG_PROC
    scripts/config --enable CONFIG_CGROUPS
    scripts/config --enable CONFIG_MEMCG
    scripts/config --enable CONFIG_CGROUP_SCHED
    scripts/config --enable CONFIG_FAIR_GROUP_SCHED
    scripts/config --disable CONFIG_RT_GROUP_SCHED
    scripts/config --enable CONFIG_INET
    scripts/config --enable CONFIG_IPV6
    scripts/config --enable CONFIG_EFI
    scripts/config --enable CONFIG_EFI_STUB
    scripts/config --enable CONFIG_FB
    scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE
    scripts/config --enable CONFIG_EXT4_FS
    scripts/config --enable CONFIG_VFAT_FS
    scripts/config --enable CONFIG_NLS_ISO8859_1
    scripts/config --enable CONFIG_DEVTMPFS
    scripts/config --enable CONFIG_DEVTMPFS_MOUNT
    scripts/config --enable CONFIG_INOTIFY_USER
    scripts/config --enable CONFIG_TMPFS
    scripts/config --enable CONFIG_TMPFS_POSIX_ACL
    scripts/config --enable CONFIG_AUTOFS_FS
    scripts/config --enable CONFIG_NET
    scripts/config --enable CONFIG_PACKET
    scripts/config --enable CONFIG_UNIX
    scripts/config --enable CONFIG_SYSVIPC
    scripts/config --enable CONFIG_SIGNALFD
    scripts/config --enable CONFIG_TIMERFD
    scripts/config --enable CONFIG_EPOLL
    scripts/config --enable CONFIG_FHANDLE
    scripts/config --enable CONFIG_SECCOMP
    make olddefconfig
  fi
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

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
}
