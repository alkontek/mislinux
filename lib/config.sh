# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Load KEY=VALUE from misl.conf. No eval. Already-set environment wins.

_misl_set_default() {
  local key=$1 val=$2
  if [[ -z ${!key+x} ]]; then
    printf -v "$key" '%s' "$val"
    export "$key"
  fi
}

_misl_unquote() {
  local val=$1
  if [[ $val == \"*\" && $val != \" ]]; then
    val=${val#\"}
    val=${val%\"}
  elif [[ $val == \'*\' && $val != \' ]]; then
    val=${val#\'}
    val=${val%\'}
  fi
  printf '%s' "$val"
}

_misl_load_file() {
  local file=$1 line key val
  [[ -f $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line%"${line##*[![:space:]]}"}
    line=${line#"${line%%[![:space:]]*}"}
    [[ -n $line ]] || continue
    [[ $line == *=* ]] || die "bad config line in $file: $line"
    key=${line%%=*}
    val=${line#*=}
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "bad config key in $file: $key"
    val=$(_misl_unquote "$val")
    if [[ -z ${!key+x} ]]; then
      printf -v "$key" '%s' "$val"
      export "$key"
    fi
  done < "$file"
}

# farpoint -> Farpoint (os-release VERSION / PRETTY_NAME display form)
misl_codename_display() {
  local c=${1:-}
  [[ -n $c ]] || return 0
  printf '%s%s' "$(printf '%s' "${c:0:1}" | tr '[:lower:]' '[:upper:]')" "${c:1}"
}

# Compose the file that becomes $LFS/etc/os-release (and usr/lib/os-release).
# 0.2 emits VERSION_ID=0.2 with no codename. Farpoint fields apply when
# MISL_VERSION equals MISL_DIST_VERSION (1.0).
misl_os_release_text() {
  local ver=$MISL_VERSION pretty=$MISL_PRETTY_NAME
  if [[ -n ${MISL_VERSION_CODENAME:-} ]]; then
    ver="$MISL_VERSION ($(misl_codename_display "$MISL_VERSION_CODENAME"))"
  fi
  printf 'NAME="%s"\n' "$MISL_NAME"
  printf 'VERSION="%s"\n' "$ver"
  printf 'ID=%s\n' "$MISL_ID"
  printf 'VERSION_ID="%s"\n' "$MISL_VERSION_ID"
  [[ -n ${MISL_VERSION_CODENAME:-} ]] && printf 'VERSION_CODENAME=%s\n' "$MISL_VERSION_CODENAME"
  printf 'PRETTY_NAME="%s"\n' "$pretty"
  printf 'VARIANT="%s"\n' "$MISL_VARIANT"
  printf 'VARIANT_ID=%s\n' "$MISL_VARIANT_ID"
}

misl_write_os_release() {
  require_lfs_set
  local text dest=$LFS/usr/lib/os-release
  mkdir -pv "$LFS/usr/lib" "$LFS/etc"
  text=$(misl_os_release_text)
  printf '%s\n' "$text" >"$dest"
  if [[ -L $LFS/etc/os-release || ! -e $LFS/etc/os-release ]]; then
    ln -sfn ../usr/lib/os-release "$LFS/etc/os-release"
  else
    printf '%s\n' "$text" >"$LFS/etc/os-release"
  fi
  printf '%s\n' "$MISL_PRETTY_NAME" >"$LFS/etc/misl-release"
  info "wrote $dest ($MISL_PRETTY_NAME)"
}

misl_load_config() {
  local conf=${MISL_CONF:-$MISL_ROOT/config/misl.conf}

  _misl_load_file "$conf"

  _misl_set_default MISL_VERSION "$(tr -d '[:space:]' < "$MISL_ROOT/VERSION")"
  _misl_set_default MISL_NAME "MIS Linux"
  _misl_set_default MISL_ID misl
  _misl_set_default MISL_DIST_VERSION 1.0
  _misl_set_default MISL_DIST_CODENAME farpoint
  _misl_set_default MISL_VERSION_ID "$MISL_VERSION"
  _misl_set_default MISL_VARIANT systemd
  _misl_set_default MISL_VARIANT_ID "$MISL_VARIANT"
  if [[ $MISL_VERSION == "$MISL_DIST_VERSION" ]]; then
    _misl_set_default MISL_VERSION_CODENAME "$MISL_DIST_CODENAME"
    _misl_set_default MISL_PRETTY_NAME \
      "$MISL_NAME $MISL_VERSION ($(misl_codename_display "$MISL_DIST_CODENAME"))"
  else
    _misl_set_default MISL_VERSION_CODENAME ""
    _misl_set_default MISL_PRETTY_NAME "$MISL_NAME $MISL_VERSION"
  fi
  _misl_set_default MISL_ARCH x86_64
  _misl_set_default MISL_FSTYPE ext4
  _misl_set_default MISL_BOOT_MIB 1024
  # Target firmware, not the host's. VPS is a build box; real metal is EFI.
  # auto = look at /sys/firmware/efi on the host.
  _misl_set_default MISL_FIRMWARE efi
  _misl_set_default MISL_HOSTNAME misl
  _misl_set_default MISL_LANG C.UTF-8
  _misl_set_default MISL_TIMEZONE UTC
  _misl_set_default MISL_KEYMAP us
  _misl_set_default MISL_DRY_RUN 1
  _misl_set_default MISL_FETCH 1
  _misl_set_default MISL_MIRROR https://makeitsolinux.org/downloads/misl-1.0-systemd
  _misl_set_default MISL_ALLOW_HOST_DISK 0
  _misl_set_default LFS_TGT x86_64-lfs-linux-gnu
  # Empty in misl.conf means "compute". Cap by RAM (~1.5GiB/job) so a
  # 2C/4G DigitalOcean box gets -j2 instead of swapping during gcc.
  if [[ -z ${MISL_MAKEFLAGS:-} ]]; then
    local jobs mem_kb maxj
    jobs=$(nproc 2>/dev/null || echo 1)
    mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    if ((mem_kb > 0)); then
      maxj=$((mem_kb / 1500000))
      ((maxj < 1)) && maxj=1
      ((jobs > maxj)) && jobs=$maxj
    fi
    MISL_MAKEFLAGS="-j${jobs}"
    export MISL_MAKEFLAGS
  fi

  # Host-wide snapshot, shared with user lfs. Created by sources fetch.
  _misl_set_default MISL_SNAPSHOT /var/cache/misl/misl-1.0-systemd
  if [[ $MISL_SNAPSHOT != /* ]]; then
    if command -v realpath >/dev/null 2>&1; then
      MISL_SNAPSHOT=$(realpath -m "$MISL_ROOT/$MISL_SNAPSHOT")
    else
      MISL_SNAPSHOT="$MISL_ROOT/$MISL_SNAPSHOT"
    fi
    export MISL_SNAPSHOT
  fi

  [[ -n ${MISL_WGET_LIST:-} ]] || MISL_WGET_LIST="$MISL_SNAPSHOT/wget-list"
  [[ -n ${MISL_MD5SUMS:-} ]] || MISL_MD5SUMS="$MISL_SNAPSHOT/md5sums"
  [[ -n ${MISL_PATCHES:-} ]] || MISL_PATCHES="$MISL_SNAPSHOT/patches"
  [[ -n ${MISL_SOURCES:-} ]] || MISL_SOURCES="$MISL_SNAPSHOT/sources"
  export MISL_WGET_LIST MISL_MD5SUMS MISL_PATCHES MISL_SOURCES MISL_SNAPSHOT MISL_MIRROR MISL_FETCH

  [[ $MISL_VERSION =~ ^[0-9]+\.[0-9]+$ ]] || \
    die "MISL_VERSION=$MISL_VERSION is not major.minor (no patch component)"
  [[ $MISL_VERSION_ID =~ ^[0-9]+\.[0-9]+$ ]] || \
    die "MISL_VERSION_ID=$MISL_VERSION_ID is not major.minor"
  [[ $MISL_DIST_VERSION =~ ^[0-9]+\.[0-9]+$ ]] || \
    die "MISL_DIST_VERSION=$MISL_DIST_VERSION is not major.minor"
  [[ $MISL_ID == misl ]] || die "MISL_ID=$MISL_ID; expected misl"
  [[ $MISL_VARIANT == systemd ]] || die "MISL_VARIANT=$MISL_VARIANT is not supported"
  [[ $MISL_VARIANT_ID == "$MISL_VARIANT" ]] || \
    die "MISL_VARIANT_ID=$MISL_VARIANT_ID must match MISL_VARIANT=$MISL_VARIANT"
  [[ $MISL_ARCH == x86_64 ]] || die "MISL_ARCH=$MISL_ARCH is not supported in 0.2"
  [[ $MISL_BOOT_MIB =~ ^[1-9][0-9]*$ ]] || die "MISL_BOOT_MIB=$MISL_BOOT_MIB is not a positive integer"
  case ${MISL_FIRMWARE,,} in
    efi|uefi|bios|auto) ;;
    *) die "MISL_FIRMWARE=$MISL_FIRMWARE (want efi|bios|auto)" ;;
  esac
  [[ $(basename "$MISL_WGET_LIST") != wget-list.original ]] || die "refusing wget-list.original"
}
