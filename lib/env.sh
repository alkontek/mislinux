# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Chapter 4 layout, lfs user, stripped environment.

misl_layout() {
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS does not exist"
  mkdir -pv "$LFS"/{etc,var,usr/{bin,lib,sbin,src/misl/{SOURCES,SPECS,SRPMS,RPMS/x86_64,RPMS/noarch}},tools}
  mkdir -pv "$LFS/var/lib/misl"/{stamps,logs,pkglog}
  misl_write_os_release
  case $MISL_ARCH in
    x86_64)
      ln -sfv usr/lib "$LFS/lib64" 2>/dev/null || ln -sfv usr/lib "$LFS/lib64"
      ln -sfv usr/bin "$LFS/bin"
      ln -sfv usr/sbin "$LFS/sbin"
      ln -sfv usr/lib "$LFS/lib"
      ;;
  esac
}

misl_lfs_home() {
  local home
  home=$(getent passwd lfs | awk -F: '{print $6}')
  [[ -n $home ]] || die "lfs user missing; run prep first"
  printf '%s\n' "$home"
}

# Book 4.3 plus the MISL stamp/log/src tree. Chapter 5 writes logs here.
misl_lfs_grant_target() {
  require_root
  require_lfs_set
  mkdir -pv "$LFS/var/lib/misl"/{stamps,logs,pkglog} \
            "$LFS/usr/src/misl"/{SOURCES,SPECS,SRPMS,RPMS/x86_64,RPMS/noarch,build} \
            "$LFS/tools"
  chown -v lfs:lfs "$LFS"/{usr,lib,var,etc,bin,sbin,tools} 2>/dev/null || true
  [[ -e $LFS/lib64 ]] && chown -v lfs:lfs "$LFS/lib64" || true
  chown -R lfs:lfs "$LFS/usr" "$LFS/var" "$LFS/tools" "$LFS/etc"
  info "granted lfs write on $LFS/{usr,var,tools,etc}"
}

# Scripts must live where user lfs can read them. /root is mode 700, so
# copy mislinux/ into ~lfs. Do not copy snapshot tarballs — they are
# already staged under $LFS/usr/src/misl/SOURCES. Catalog files are small.
misl_lfs_publish_bootstrap() {
  require_root
  local home dest snapdest
  home=$(misl_lfs_home)
  dest=$home/mislinux
  mkdir -pv "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.git/' --exclude 'logs/' --exclude 'stamps/' \
      "$MISL_ROOT"/ "$dest"/
  else
    cp -a "$MISL_ROOT"/. "$dest"/
  fi
  misl_snapshot_share
  if [[ -e $home/misl-1.0-systemd && ! -L $home/misl-1.0-systemd ]]; then
    warn "leaving $home/misl-1.0-systemd in place; snapshot is $MISL_SNAPSHOT"
  else
    ln -sfn "$MISL_SNAPSHOT" "$home/misl-1.0-systemd"
  fi
  chown -R lfs:lfs "$dest"
  chown -h lfs:lfs "$home/misl-1.0-systemd" 2>/dev/null || true
  info "published bootstrap at $dest snapshot=$MISL_SNAPSHOT"
}

misl_lfs_user() {
  require_root
  require_lfs_set
  getent group lfs >/dev/null 2>&1 || groupadd lfs
  if ! getent passwd lfs >/dev/null 2>&1; then
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs
  fi
  misl_lfs_grant_target
  misl_snapshot_share
}

misl_environment() {
  require_root
  local home
  home=$(getent passwd lfs | awk -F: '{print $6}')
  [[ -n $home ]] || die "lfs user missing; run prep first"
  cat > "$home/.bash_profile" <<'EOF'
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF
  cat > "$home/.bashrc" <<EOF
set +h
umask 022
LFS=${LFS}
LC_ALL=POSIX
LFS_TGT=${LFS_TGT}
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:\$PATH; fi
PATH=\$LFS/tools/bin:\$PATH
CONFIG_SITE=\$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
export MAKEFLAGS=${MISL_MAKEFLAGS}
EOF
  chown lfs:lfs "$home/.bash_profile" "$home/.bashrc"
  info "wrote $home/.bash_profile and .bashrc"
}

misl_prep() {
  local extra=${1:-}
  misl_layout
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    misl_lfs_user
    misl_environment
    case $extra in
      publish) misl_lfs_publish_bootstrap ;;
      "")
        if ! runuser -u lfs -- test -r "$MISL_ROOT/misl" 2>/dev/null; then
          warn "lfs cannot read $MISL_ROOT; publishing bootstrap into $(misl_lfs_home)"
          misl_lfs_publish_bootstrap
        fi
        ;;
      *) die "usage: misl prep [publish]" ;;
    esac
  else
    warn "not root: created layout only; skip lfs user and environment"
  fi
}
