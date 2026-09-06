# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# sbcl-2.6.10: Steel Bank Common Lisp, group=lisp (opt-in).
# SBCL builds itself with an existing SBCL. The x86-64 binary from
# mirror incoming/ is unpacked into a scratch dir, used as --xc-host,
# and deleted. It is never installed.

pkg_name=sbcl
pkg_version=2.6.10
pkg_tarball=sbcl-2.6.10-source.tar.bz2
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="zlib"

SBCL_BOOTSTRAP_TARBALL=sbcl-2.6.10-x86-64-linux-binary.tar.bz2

_sbcl_bootstrap_tarball() {
  local d
  for d in "$(misl_lfs_join usr/src/misl/SOURCES)" \
           "${MISL_SNAPSHOT:+$MISL_SNAPSHOT/incoming}" \
           "${MISL_SOURCES:-}"; do
    [[ -n $d && -f $d/$SBCL_BOOTSTRAP_TARBALL ]] && { printf '%s\n' "$d/$SBCL_BOOTSTRAP_TARBALL"; return 0; }
  done
  return 1
}

# md5: MISL_SBCL_BOOTSTRAP_MD5, else a <tarball>.md5 sidecar written by
# sources stage (from md5sums when the mirror lists it). Neither: warn.
_sbcl_bootstrap_md5() {
  local tb=$1
  if [[ -n ${MISL_SBCL_BOOTSTRAP_MD5:-} ]]; then
    printf '%s\n' "$MISL_SBCL_BOOTSTRAP_MD5"
  elif [[ -s $tb.md5 ]]; then
    awk '{print $1; exit}' "$tb.md5"
  fi
}

pkg_pre_configure() {
  [[ -f version.lisp-expr ]] || die "sbcl source has no version.lisp-expr"
  grep -q '"2\.6\.10"' version.lisp-expr || die "version.lisp-expr is not 2.6.10"
  local tb want got
  tb=$(_sbcl_bootstrap_tarball) || die "sbcl bootstrap $SBCL_BOOTSTRAP_TARBALL not staged (MISL_GROUPS=lisp misl sources fetch/stage)"
  want=$(_sbcl_bootstrap_md5 "$tb")
  if [[ -n $want ]]; then
    got=$(md5sum "$tb" | awk '{print $1}')
    [[ $got == "$want" ]] || die "sbcl bootstrap md5 mismatch: $got != $want"
  else
    warn "sbcl bootstrap: no md5 configured (MISL_SBCL_BOOTSTRAP_MD5); not verified"
  fi
  SBCL_SCRATCH=$PWD/.misl-sbcl-bootstrap
  rm -rf "$SBCL_SCRATCH"
  mkdir -p "$SBCL_SCRATCH"
  tar -xf "$tb" -C "$SBCL_SCRATCH" --strip-components=1
  [[ -x $SBCL_SCRATCH/run-sbcl.sh ]] || die "bootstrap has no run-sbcl.sh"
}

pkg_build() {
  # SBCL_HOME from the environment would confuse both host and target.
  env -u SBCL_HOME sh make.sh --prefix=/usr --fancy \
    --xc-host="$SBCL_SCRATCH/run-sbcl.sh --non-interactive --no-sysinit --no-userinit"
  # Info manual only if makeinfo works; no PDF/HTML (texlive).
  SBCL_INFO=0
  if command -v makeinfo >/dev/null 2>&1 && makeinfo --version >/dev/null 2>&1; then
    if make -C doc/manual info; then
      SBCL_INFO=1
    else
      warn "sbcl info manual failed; continuing without it"
    fi
  else
    warn "makeinfo not usable; sbcl info manual skipped"
  fi
}

pkg_install() {
  local dest
  dest=$(misl_dest)
  env -u SBCL_HOME INSTALL_ROOT=/usr BUILD_ROOT="$dest" sh install.sh
  if [[ ${SBCL_INFO:-0} != 1 ]]; then
    rm -f "${dest}"/usr/share/info/sbcl.info* "${dest}"/usr/share/info/asdf.info*
  fi
  rm -rf "$SBCL_SCRATCH"
  [[ -x ${dest}/usr/bin/sbcl ]] || die "sbcl missing after install"
  [[ -f ${dest}/usr/lib/sbcl/sbcl.core ]] || die "sbcl.core missing after install"
}

pkg_check() {
  [[ ! -e ${SBCL_SCRATCH:-/nonexistent} ]] || die "bootstrap scratch dir left behind"
  misl_check_run /usr/bin/sbcl --version
  misl_check_run sh -c "/usr/bin/sbcl --non-interactive --no-sysinit --no-userinit --eval '(print (+ 1 2))' | grep -Eq '^3 ?$'"
}
