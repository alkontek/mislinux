# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Chapter 7: ownership, virtfs, essential files, enter.

misl_in_chroot() {
  [[ -e /proc/1/root ]] || return 1
  local a b
  a=$(stat -c %d:%i / 2>/dev/null || true)
  b=$(stat -c %d:%i /proc/1/root 2>/dev/null || true)
  [[ -n $a && -n $b && $a != "$b" ]]
}

# Install prefix for ch7+. Empty inside the chroot (DESTDIR unused).
misl_dest() {
  if misl_in_chroot || [[ ${LFS:-} == / ]]; then
    printf '\n'
  else
    printf '%s\n' "${LFS:?}"
  fi
}

misl_kernfs_mount() {
  require_root
  require_lfs_set
  [[ $LFS != / ]] || die "refusing kernfs on LFS=/"
  mkdir -pv "$LFS"/{dev,proc,sys,run}
  mountpoint -q "$LFS/dev" || mount -v --bind /dev "$LFS/dev"
  if ! mountpoint -q "$LFS/dev/pts"; then
    mkdir -pv "$LFS/dev/pts"
    mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
  fi
  mountpoint -q "$LFS/proc" || mount -vt proc proc "$LFS/proc"
  mountpoint -q "$LFS/sys"  || mount -vt sysfs sysfs "$LFS/sys"
  mountpoint -q "$LFS/run"  || mount -vt tmpfs tmpfs "$LFS/run"
  if [[ ${MISL_FIRMWARE:-efi} == efi ]]; then
    misl_disk_resolve_parts 2>/dev/null || true
    mkdir -pv "$LFS/boot/efi"
    if [[ -n ${MISL_PART_BOOT:-} && -e ${MISL_PART_BOOT} ]]; then
      mountpoint -q "$LFS/boot/efi" || mount "$MISL_PART_BOOT" "$LFS/boot/efi"
    fi
  fi
  if [[ -h $LFS/dev/shm ]]; then
    install -v -d -m 1777 "$LFS$(realpath /dev/shm 2>/dev/null || echo /dev/shm)"
  else
    mkdir -pv "$LFS/dev/shm"
    mountpoint -q "$LFS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
  fi
}

misl_chroot_owner() {
  require_root
  require_lfs_set
  chown --from lfs -R root:root "$LFS"/{usr,var,etc,tools} 2>/dev/null || \
    chown -R root:root "$LFS"/{usr,var,etc,tools}
  if [[ -e $LFS/lib64 ]]; then
    chown --from lfs -R root:root "$LFS/lib64" 2>/dev/null || \
      chown -R root:root "$LFS/lib64"
  fi
}

misl_chroot_dirs() {
  local root=${1:-${LFS:?}}
  mkdir -pv "$root"/{boot,home,mnt,opt,srv}
  mkdir -pv "$root"/etc/{opt,sysconfig}
  mkdir -pv "$root"/lib/firmware
  mkdir -pv "$root"/media/{floppy,cdrom}
  mkdir -pv "$root"/usr/{,local/}{include,src}
  mkdir -pv "$root"/usr/lib/locale
  mkdir -pv "$root"/usr/local/{bin,lib,sbin}
  mkdir -pv "$root"/usr/{,local/}share/{color,dict,doc,info,locale,man}
  mkdir -pv "$root"/usr/{,local/}share/{misc,terminfo,zoneinfo}
  mkdir -pv "$root"/usr/{,local/}share/man/man{1..8}
  mkdir -pv "$root"/var/{cache,local,log,mail,opt,spool}
  mkdir -pv "$root"/var/lib/{color,misc,locate}
  ln -sfv /run "$root"/var/run
  ln -sfv /run/lock "$root"/var/lock
  install -dv -m 0750 "$root"/root
  install -dv -m 1777 "$root"/tmp "$root"/var/tmp
}

misl_chroot_files() {
  local root=${1:-${LFS:?}}
  ln -sfv /proc/self/mounts "$root"/etc/mtab
  cat > "$root"/etc/hosts <<EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF
  cat > "$root"/etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
tester:x:101:101::/home/tester:/bin/bash
EOF
  cat > "$root"/etc/group <<'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
tester:x:101:
EOF
  install -dv -m 0755 "$root"/home/tester
  touch "$root"/var/log/{btmp,lastlog,faillog,wtmp}
  chgrp -v utmp "$root"/var/log/lastlog 2>/dev/null || true
  chmod -v 664 "$root"/var/log/lastlog
  chmod -v 600 "$root"/var/log/btmp
}

misl_chroot_publish() {
  require_root
  require_lfs_set
  local dest snap
  dest=$LFS/usr/src/misl/mislinux
  snap=$LFS/usr/src/misl/misl-1.0-systemd
  mkdir -pv "$dest" "$snap"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude '.git/' --exclude 'logs/' --exclude 'stamps/' \
      "$MISL_ROOT"/ "$dest"/
  else
    cp -a "$MISL_ROOT"/. "$dest"/
  fi
  [[ -f $MISL_WGET_LIST ]] && cp -a "$MISL_WGET_LIST" "$snap/wget-list"
  [[ -f $MISL_MD5SUMS ]] && cp -a "$MISL_MD5SUMS" "$snap/md5sums"
  if [[ -d $LFS/usr/src/misl/SOURCES ]]; then
    rm -rf "$snap/sources"
    ln -sfn /usr/src/misl/SOURCES "$snap/sources"
  fi
  if [[ -d $MISL_PATCHES ]]; then
    mkdir -pv "$snap/patches"
    cp -a "$MISL_PATCHES"/. "$snap/patches/"
  fi
  cat > "$LFS/root/.bash_profile" <<'EOF'
export LFS=/
export PATH=/usr/bin:/usr/sbin
cd /usr/src/misl/mislinux 2>/dev/null || true
EOF
  info "published bootstrap at $dest"
}

misl_chroot_prep() {
  require_root
  require_lfs_set
  [[ -x $LFS/usr/bin/bash || -x $LFS/bin/bash ]] || \
    die "no bash in $LFS; finish 06-temp first"
  misl_chroot_owner
  misl_chroot_dirs "$LFS"
  misl_chroot_files "$LFS"
  misl_kernfs_mount
  misl_chroot_publish
  info "chroot ready. as root: misl enter"
}

misl_bind_bootstrap() {
  require_root
  require_lfs_set
  local dest=$LFS/usr/src/misl/mislinux
  mkdir -pv "$dest"
  if mountpoint -q "$dest"; then
    info "bootstrap already bound at $dest"
    return 0
  fi
  # Live host tree, not a stale chroot-prep snapshot.
  mount --bind "$MISL_ROOT" "$dest"
  info "bound $MISL_ROOT -> $dest"
}

misl_enter() {
  require_root
  require_lfs_set
  [[ -x $LFS/usr/bin/env || -x $LFS/bin/bash ]] || \
    die "target has no /usr/bin/env; finish 06-temp and misl chroot prep"
  misl_kernfs_mount
  misl_bind_bootstrap
  info "entering $LFS (LFS=/ inside). scripts are $MISL_ROOT bound at /usr/src/misl/mislinux"
  exec chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-linux}" \
    PS1='(misl chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig \
    LFS=/ \
    MAKEFLAGS="${MISL_MAKEFLAGS:--j2}" \
    MISL_MAKEFLAGS="${MISL_MAKEFLAGS:--j2}" \
    /bin/bash --login +h
}
