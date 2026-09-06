# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# strace-7.2: x86_64 only, no multi-personality.

pkg_name=strace
pkg_version=7.2
pkg_tarball=strace-7.2.tar.xz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires=""

pkg_configure() {
  # No 32-bit glibc in MISL: mpers would fail. libdw (-k) autodetected.
  ./configure --prefix=/usr \
              --enable-mpers=no \
              --disable-gcc-Werror
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
  else
    make install
  fi
  [[ -x ${dest}/usr/bin/strace ]] || die "strace missing after install"
}

# Runs in the build dir (recipe_main cd's there), so config.h is the
# one this binary was built from.
pkg_check() {
  local v
  grep -Eq '^#define HAVE_(M32|MX32)_MPERS 1' config.h && \
    die "strace built with mpers (config.h)"
  if [[ -z $(misl_dest) ]]; then
    v=$(/usr/bin/strace -V) || die "strace -V failed"
    printf '%s\n' "$v"
    # Feature line lists no-m32-mpers/no-mx32-mpers when disabled.
    grep -Eq '(^|[[:space:]])m(x)?32-mpers' <<<"$v" && die "strace -V reports mpers"
    # ptrace may be denied (seccomp/Yama on the host): warn, don't fail.
    /usr/bin/strace -f -o /dev/null /usr/bin/true || \
      warn "strace trace test failed (ptrace blocked in this context?)"
  else
    warn "check skipped (DESTDIR install): strace -V"
  fi
}
