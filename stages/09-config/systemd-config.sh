# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# LFS 13.1-systemd chapter 9 (no prompts).
pkg_name=systemd-config
pkg_version=261.2
pkg_tarball=systemd-261.2.tar.gz
pkg_patches=
pkg_stage=09-config
pkg_pass=1
# 0.2 writes a placeholder os-release at prep from config identity vars.
# This stage will refresh it (and the rest of chapter 9) in a later minor.
pkg_configure() { die "stub: systemd-config not implemented in 0.2"; }
pkg_unpack=no
pkg_builddir=in-tree

pkg_configure() { :; }
pkg_build() { :; }

pkg_install() {
  local dest host lang tz keymap root_dev boot_dev root_uuid boot_uuid
  dest=$(misl_dest)
  host=${MISL_HOSTNAME:-misl}
  lang=${MISL_LANG:-C.UTF-8}
  tz=${MISL_TIMEZONE:-UTC}
  keymap=${MISL_KEYMAP:-us}

  mkdir -pv "${dest}/etc/systemd/network" \
            "${dest}/etc/systemd/system" \
            "${dest}/etc/vconsole.conf.d" \
            "${dest}/boot/efi" \
            "${dest}/usr/lib"

  printf '%s\n' "$host" > "${dest}/etc/hostname"

  printf '%s\n' \
    '# Begin /etc/hosts' \
    '127.0.0.1 localhost.localdomain localhost' \
    "127.0.1.1 ${host}.localdomain ${host}" \
    '::1       localhost ip6-localhost ip6-loopback' \
    'ff02::1   ip6-allnodes' \
    'ff02::2   ip6-allrouters' \
    '# End /etc/hosts' \
    > "${dest}/etc/hosts"

  printf '%s\n' \
    '[Match]' \
    'Name=en* eth*' \
    '' \
    '[Network]' \
    'DHCP=yes' \
    '' \
    '[DHCPv4]' \
    'UseDomains=true' \
    > "${dest}/etc/systemd/network/20-dhcp.network"

  printf '%s\n' "LANG=${lang}" > "${dest}/etc/locale.conf"
  printf '%s\n' "KEYMAP=${keymap}" > "${dest}/etc/vconsole.conf"

  printf '%s\n' \
    '# Begin /etc/profile' \
    'for i in $(locale); do' \
    '  unset ${i%=*}' \
    'done' \
    'if [[ "$TERM" = linux ]]; then' \
    '  export LANG=C.UTF-8' \
    'else' \
    '  [[ -f /etc/locale.conf ]] && . /etc/locale.conf' \
    '  export LANG' \
    'fi' \
    'export PATH=/usr/bin:/usr/sbin' \
    '# End /etc/profile' \
    > "${dest}/etc/profile"

  printf '%s\n' \
    '# Begin /etc/inputrc' \
    'set horizontal-scroll-mode Off' \
    'set meta-flag On' \
    'set input-meta On' \
    'set convert-meta Off' \
    'set output-meta On' \
    'set bell-style none' \
    '"\eOd": backward-word' \
    '"\eOc": forward-word' \
    '# End /etc/inputrc' \
    > "${dest}/etc/inputrc"

  printf '%s\n' '/bin/sh' '/bin/bash' '/usr/bin/bash' > "${dest}/etc/shells"

  printf '%s\n' '0.0 0 0.0' '0' 'UTC' > "${dest}/etc/adjtime"
  if [[ -e /usr/share/zoneinfo/${tz} ]]; then
    ln -sfv "/usr/share/zoneinfo/${tz}" "${dest}/etc/localtime"
  fi

  misl_disk_resolve_parts 2>/dev/null || true
  root_dev=${MISL_PART_ROOT:-}
  boot_dev=${MISL_PART_BOOT:-}
  root_uuid=
  boot_uuid=
  if command -v blkid >/dev/null 2>&1; then
    [[ -n $root_dev && -e $root_dev ]] && root_uuid=$(blkid -s UUID -o value "$root_dev" || true)
    [[ -n $boot_dev && -e $boot_dev ]] && boot_uuid=$(blkid -s UUID -o value "$boot_dev" || true)
  fi

  {
    printf '%s\n' '# /etc/fstab — MIS Linux'

    if [[ -n $root_uuid ]]; then
      printf 'UUID=%s         /               %s            defaults               1 1\n' "$root_uuid" "${MISL_FSTYPE:-ext4}"
    elif [[ -n $root_dev ]]; then
      printf '%s              /               %s            defaults               1 1\n' "$root_dev" "${MISL_FSTYPE:-ext4}"
    else
      printf '# set root= after blkid is available\n'
    fi

    if [[ ${MISL_FIRMWARE:-efi} == efi ]]; then
      if [[ -n $boot_uuid ]]; then
        printf 'UUID=%s         /boot/efi           vfat      defaults,umask=0077    0 2\n' "$boot_uuid"
      elif [[ -n $boot_dev ]]; then
        printf '%s              /boot/efi           vfat      defaults,umask=0077    0 2\n' "$boot_dev"
      fi
    else
      if [[ -n $boot_uuid ]]; then
        printf 'UUID=%s         /boot               %s        defaults               0 2\n' "$boot_uuid" "${MISL_FSTYPE:-ext4}"
      elif [[ -n $boot_dev ]]; then
        printf '%s              /boot               %s        defaults               0 2\n' "$boot_dev" "${MISL_FSTYPE:-ext4}"
      fi
    fi

    printf 'proc            /proc               proc      defaults               0 0\n'
    printf 'sysfs           /sys                sysfs     defaults               0 0\n'
    printf 'devpts          /dev/pts            devpts    gid=5,mode=620         0 0\n'
    printf 'tmpfs           /run                tmpfs     defaults               0 0\n'
  } > "${dest}/etc/fstab"

  local save=$LFS
  LFS=${dest:-/}
  misl_write_os_release
  LFS=$save

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable systemd-networkd || true
    systemctl enable systemd-resolved || true
    systemctl enable systemd-timesyncd || true
  fi

  if [[ -n ${MISL_ROOT_HASH:-} ]]; then
    command -v chpasswd >/dev/null 2>&1 && \
      printf 'root:%s\n' "$MISL_ROOT_HASH" | chpasswd -e || true
  else
    info "root password not set (export MISL_ROOT_HASH=... from openssl passwd -6)"
  fi

  mkdir -pv "${dest}/var/lib/misl"
  {
    printf 'MIS Linux %s chapter 9 config\n' "$MISL_VERSION"
    printf 'hostname=%s\n' "$host"
    printf 'LANG=%s KEYMAP=%s TIMEZONE=%s\n' "$lang" "$keymap" "$tz"
    printf 'firmware=%s\n' "${MISL_FIRMWARE:-efi}"
    printf 'root_dev=%s root_uuid=%s\n' "${root_dev:-unset}" "${root_uuid:-unset}"
    printf 'boot_dev=%s boot_uuid=%s\n' "${boot_dev:-unset}" "${boot_uuid:-unset}"
    printf 'sshd=enabled (if unit present)\n'
    printf 'networkd=DHCP on en* eth*\n'
    if [[ -n ${MISL_ROOT_HASH:-} ]]; then
      printf 'root_password=hash-applied\n'
    else
      printf 'root_password=UNSET\n'
    fi
    printf '\n--- /etc/hostname ---\n'
    cat "${dest}/etc/hostname" 2>/dev/null || true
    printf '\n--- /etc/fstab ---\n'
    cat "${dest}/etc/fstab" 2>/dev/null || true
    printf '\n--- /etc/hosts ---\n'
    cat "${dest}/etc/hosts" 2>/dev/null || true
    printf '\n--- /etc/systemd/network/20-dhcp.network ---\n'
    cat "${dest}/etc/systemd/network/20-dhcp.network" 2>/dev/null || true
    printf '\n--- /etc/os-release ---\n'
    cat "${dest}/etc/os-release" 2>/dev/null || true
  } | tee "${dest}/var/lib/misl/09-config.report"
}

pkg_report() {
  local dest report
  dest=$(misl_dest)
  report=${dest}/var/lib/misl/09-config.report
  if [[ -f $report ]]; then
    info "09-config report ($report)"
    cat "$report"
  else
    info "no 09-config report yet; MISL_FORCE=1 ./misl build 09-config/systemd-config"
  fi
}
