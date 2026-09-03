# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Recipe runner. Stamps live on the target disk.

# LFS=/ inside chroot must not produce //usr/...
misl_lfs_join() {
  local root=${LFS:-/}
  root=${root%/}
  printf '%s/%s\n' "$root" "${1#/}"
}

recipe_reset() {
  unset pkg_name pkg_version pkg_tarball pkg_patches pkg_stage pkg_pass pkg_builddir pkg_unpack
  unset -f pkg_pre_configure pkg_configure pkg_build pkg_install pkg_post_install 2>/dev/null || true
}

recipe_stamp() {
  printf '%s/%s-%s-%s.done\n' \
    "$(misl_lfs_join var/lib/misl/stamps)" "${pkg_stage:?}" "${pkg_name:?}" "${pkg_pass:-1}"
}

recipe_log() {
  printf '%s/%s-%s-%s.log\n' \
    "$(misl_lfs_join var/lib/misl/logs)" "${pkg_stage:?}" "${pkg_name:?}" "${pkg_pass:-1}"
}

recipe_find_tarball() {
  local name=$1 path
  if [[ -n ${LFS:-} && -f $(misl_lfs_join usr/src/misl/SOURCES/"$name") ]]; then
    printf '%s\n' "$(misl_lfs_join usr/src/misl/SOURCES/"$name")"
    return 0
  fi
  if path=$(misl_locate "$name" 2>/dev/null); then
    printf '%s\n' "$path"
    return 0
  fi
  return 1
}

recipe_require_tarball() {
  local name=$1 path
  path=$(recipe_find_tarball "$name") || die "tarball not staged: $name"
  printf '%s\n' "$path"
}

recipe_preflight() {
  local path expect actual
  path=$(recipe_find_tarball "$pkg_tarball") || die "tarball not staged: $pkg_tarball (other wget-list files may still be missing)"
  if expect=$(misl_md5_for "$pkg_tarball" 2>/dev/null); then
    actual=$(md5sum "$path" | awk '{print $1}')
    [[ $actual == "$expect" ]] || die "HASH-MISMATCH $pkg_tarball expected=$expect got=$actual"
    info "preflight OK $pkg_tarball md5=$actual"
  else
    info "preflight OK $pkg_tarball (no md5 in list)"
  fi
  RECIPE_TARBALL_PATH=$path
}

recipe_main() {
  require_lfs_set
  : "${pkg_name:?}" "${pkg_version:?}" "${pkg_tarball:?}" "${pkg_stage:?}"
  pkg_pass=${pkg_pass:-1}

  if declare -F pkg_configure >/dev/null; then
    if declare -f pkg_configure | grep -q 'not implemented'; then
      die "stub: $pkg_name is not implemented"
    fi
  fi

  if [[ $pkg_stage == 05-cross || $pkg_stage == 06-temp ]]; then
    [[ ${EUID:-$(id -u)} -ne 0 ]] || die "chapter 5/6 recipes must run as user lfs, not root"
  fi
  if [[ $pkg_stage == 07-chroot-temp || $pkg_stage == 08-system || $pkg_stage == 09-config || $pkg_stage == 10-boot ]]; then
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "chapter 7+ recipes must run as root (misl enter)"
  fi

  local stamp log srcdir build tarball p patchfile hash
  stamp=$(recipe_stamp)
  log=$(recipe_log)
  mkdir -pv "$(dirname "$stamp")" "$(dirname "$log")"

  if [[ -f $stamp && ${MISL_FORCE:-0} != 1 ]]; then
    info "skip $pkg_name pass=$pkg_pass (stamp exists)"
    if declare -F pkg_report >/dev/null; then
      pkg_report
    fi
    return 0
  fi

  srcdir=$(misl_lfs_join "usr/src/misl/build/$pkg_name-$pkg_version")
  if [[ ${pkg_unpack:-yes} == no || ${pkg_tarball:-} == - ]]; then
    tarball=-
    mkdir -pv "$srcdir"
    build=$srcdir
  else
    recipe_preflight
    tarball=$RECIPE_TARBALL_PATH

    rm -rf "$srcdir"
    mkdir -pv "$srcdir"

    info "unpack $pkg_tarball"
    tar -xf "$tarball" -C "$srcdir" --strip-components=1

    pkg_patches=${pkg_patches:-}
    for p in $pkg_patches; do
      [[ $p == - || -z $p ]] && continue
      patchfile=$(misl_lfs_join "usr/src/misl/SOURCES/$p")
      [[ -f $patchfile ]] || patchfile=$MISL_PATCHES/$p
      [[ -f $patchfile ]] || die "patch missing: $p"
      info "patch $p"
      (cd "$srcdir" && patch -Np1 --batch --forward -i "$patchfile") \
        || die "patch failed: $p"
    done

    if [[ ${pkg_builddir:-build} == build ]]; then
      mkdir -pv "$srcdir/build"
      build=$srcdir/build
    else
      build=$srcdir
    fi
  fi

  info "building $pkg_name -> $log"
  set +e
  set -o pipefail
  (
    set -e
    cd "$build"
    if declare -F pkg_pre_configure >/dev/null; then pkg_pre_configure; fi
    if declare -F pkg_configure >/dev/null; then pkg_configure; fi
    if declare -F pkg_build >/dev/null; then pkg_build; fi
    if declare -F pkg_install >/dev/null; then pkg_install; fi
    if declare -F pkg_post_install >/dev/null; then pkg_post_install; fi
    if declare -F pkg_report >/dev/null; then pkg_report; fi
  ) 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}
  set +o pipefail
  set -e
  if (( rc != 0 )); then
    die "recipe failed rc=$rc $pkg_name (see $log)"
  fi

  if [[ $tarball == - || ! -f ${tarball:-} ]]; then
    hash=-
  else
    hash=$(md5sum "$tarball" | awk '{print $1}')
  fi
  mkdir -pv "$(misl_lfs_join var/lib/misl/pkglog)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$pkg_name" "$pkg_version" "$pkg_tarball" "$hash" "$pkg_stage" "$pkg_pass" \
    "$(date -u +%FT%TZ)" >>"$(misl_lfs_join var/lib/misl/pkglog/packages.tsv)"

  [[ ${MISL_KEEP_BUILD:-0} == 1 ]] || rm -rf "$srcdir"
  touch "$stamp"
  info "done $pkg_name pass=$pkg_pass"
}
