# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Fedora 44 host-dep install.

_ver_ge() {
  python3 - "$1" "$2" >/dev/null <<'PY'
import re, sys
def parts(s):
    return [int(x) for x in re.findall(r"\d+", s)[:4]] or [0]
a, b = parts(sys.argv[1]), parts(sys.argv[2])
raise SystemExit(0 if a >= b else 1)
PY
}

# Tools plus the bits this bootstrap actually invokes
# (wget, parted, mkfs.ext4, mkfs.vfat).
misl_fedora_host_rpms() {
  printf '%s\n' \
    bash binutils bison gcc gcc-c++ make patch \
    perl python3 python3-pip \
    glibc-devel \
    coreutils diffutils findutils gawk grep gzip sed tar xz \
    texinfo \
    wget \
    parted e2fsprogs dosfstools
}

# Fedora 44 no longer ships yacc, link to /usr/bin/bison instead
misl_ensure_yacc() {
  if [[ -e /usr/bin/yacc ]]; then
    return 0
  fi
  if command -v bison >/dev/null 2>&1; then
    ln -sfn "$(command -v bison)" /usr/bin/yacc
    info "linked /usr/bin/yacc -> $(readlink -f /usr/bin/yacc)"
    return 0
  fi
  return 1
}

misl_doctor_pkgs() {
  local rpms
  rpms=$(misl_fedora_host_rpms | tr '\n' ' ')
  printf 'dnf install -y %s\n' "$rpms"
}

misl_doctor_install() {
  require_root
  require_cmd dnf
  local rpms
  rpms=$(misl_fedora_host_rpms)
  info "dnf install --setopt=install_weak_deps=False -y $rpms"
  # shellcheck disable=SC2086
  dnf install --setopt=install_weak_deps=False -y $rpms
  misl_ensure_yacc || warn "bison installed but could not create /usr/bin/yacc"
  info "re-run: misl doctor"
}

misl_doctor() {
  local fail=0 warnc=0
  local issue

  issue() { misllog FAIL "$*"; fail=1; }
  note()  { warn "$*"; warnc=$((warnc + 1)); }

  info "$MISL_PRETTY_NAME doctor (id=$MISL_ID arch=$MISL_ARCH variant=$MISL_VARIANT goal=$MISL_DIST_VERSION/$MISL_DIST_CODENAME)"

  local mach
  mach=$(uname -m)
  [[ $mach == x86_64 ]] || issue "uname -m is $mach, need x86_64"

  if [[ -L /bin/sh || -e /bin/sh ]]; then
    local sh
    sh=$(readlink -f /bin/sh 2>/dev/null || true)
    [[ ${sh##*/} == bash ]] || issue "/bin/sh is $sh, need bash"
  else
    issue "/bin/sh missing"
  fi

  local kver
  kver=$(uname -r)
  _ver_ge "$kver" 5.4 || issue "kernel $kver < 5.4"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ ${ID:-} == fedora ]]; then
      [[ ${VERSION_ID:-} == 44 ]] || note "host is Fedora ${VERSION_ID:-?}, documented path is Fedora 44"
    else
      note "host ID=${ID:-unknown}, documented path is Fedora 44"
    fi
  else
    note "/etc/os-release missing"
  fi

  _need() {
    local cmd=$1 min=$2 got
    if ! command -v "$cmd" >/dev/null 2>&1; then
      issue "missing $cmd (>= $min)"
      return
    fi
    case $cmd in
      gcc|g++) got=$($cmd -dumpfullversion 2>/dev/null || $cmd -dumpversion) ;;
      ld) got=$(ld --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true) ;;
      perl) got=$(perl -e 'printf "%vd\n", $^V' 2>/dev/null || true) ;;
      *) got=$($cmd --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true) ;;
    esac
    [[ -n $got ]] || { note "could not parse $cmd version"; return; }
    _ver_ge "$got" "$min" || issue "$cmd $got < $min"
    info "found $cmd $got"
  }

  _need bash 3.2
  _need ld 2.13.1
  _need bison 2.7
  _need cat 8.1          # coreutils
  _need diff 2.8.1
  _need find 4.2.31
  _need gawk 4.0.1
  _need gcc 5.4
  _need g++ 5.4
  _need grep 2.5.1
  _need gzip 1.3.12
  _need make 4.0
  _need patch 2.5.4
  _need python3 3.4
  _need perl 5.8.8
  _need sed 4.1.5
  _need tar 1.22
  _need xz 5.0.0

  _need_link() {
    local path=$1 expect=$2
    if [[ ! -e $path ]]; then
      issue "missing $path (should be $expect)"
      return
    fi
    local dest
    dest=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
    if [[ ${dest##*/} == "$expect" || ${dest##*/} == ${expect}* ]]; then
      info "link $path -> $dest"
    else
      note "$path is $dest, book wants $expect"
    fi
  }
  _need_link /usr/bin/awk gawk
  if [[ ! -e /usr/bin/yacc ]] && command -v bison >/dev/null 2>&1; then
    note "missing /usr/bin/yacc; Fedora 44 bison does not ship it. run: misl doctor install"
  else
    _need_link /usr/bin/yacc bison
  fi

  if [[ ${ID:-} == fedora ]] && command -v rpm >/dev/null 2>&1; then
    local rpm
    for rpm in glibc-devel gcc-c++ bison; do
      if rpm -q "$rpm" >/dev/null 2>&1; then
        info "rpm $rpm installed"
      else
        issue "missing Fedora package $rpm"
      fi
    done
  fi

  if command -v gcc >/dev/null 2>&1; then
    local gv
    gv=$(gcc -dumpfullversion 2>/dev/null || gcc -dumpversion)
    if _ver_ge "$gv" 16.2.1; then
      note "host gcc $gv is newer than LFS 13.1-systemd tested ceiling 16.2.0"
    fi
  fi
  if command -v ld >/dev/null 2>&1; then
    local bv
    bv=$(ld --version | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
    if [[ -n $bv ]] && _ver_ge "$bv" 2.47.1; then
      note "host binutils $bv is newer than LFS 13.1-systemd tested ceiling 2.47.0"
    fi
  fi

  if [[ ${LFS:-} != / && -n ${LFS:-} && -d $LFS/usr/src/misl/mislinux ]]; then
    local ha hb
    ha=$(stat -c %d:%i "$MISL_ROOT/misl" 2>/dev/null || true)
    hb=$(stat -c %d:%i "$LFS/usr/src/misl/mislinux/misl" 2>/dev/null || true)
    if [[ -n $ha && -n $hb && $ha != "$hb" ]]; then
      note "$LFS/usr/src/misl/mislinux is not this tree. ./misl enter remounts it over the chroot-prep snapshot"
    elif mountpoint -q "$LFS/usr/src/misl/mislinux"; then
      info "chroot bootstrap bound to $MISL_ROOT"
    fi
  fi

  if (( fail )); then
    misllog RESULT "FAIL (warnings=$warnc)"
    return 1
  fi
  if (( warnc )); then
    misllog RESULT "OK-WITH-WARNINGS ($warnc)"
    return 0
  fi
  misllog RESULT "OK"
  return 0
}
