# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Optional docs: config/docs.manifest + mirror docs/. Not packages.
# Archives: $MISL_DOCS_DIR (host snapshot) or <root>/usr/src/misl/DOCS
# (staged by `sources stage` for MISL_DOCS, visible in the chroot).
# Ledger: <root>/var/lib/misl/docs/<name>.{files,dirs}

misl_docs_manifest() {
  printf '%s\n' "${MISL_DOCS_MANIFEST:-$MISL_ROOT/config/docs.manifest}"
}

# Is this wget-list URL a docs/ entry?
misl_is_doc_url() { [[ $1 == */docs/* ]]; }

# Docs named in MISL_DOCS (by name or tarball)?
misl_docs_wanted() {
  local t=$1 w line
  [[ ${MISL_FETCH_DOCS:-0} == 1 ]] && return 0
  for w in ${MISL_DOCS:-}; do
    [[ $w == "$t" ]] && return 0
    line=$(misl_docs_row "$w" 2>/dev/null) || continue
    [[ $(awk '{print $3}' <<<"$line") == "$t" ]] && return 0
  done
  return 1
}

# Prints the manifest row for a doc name (or tarball).
misl_docs_row() {
  local want=$1 man
  man=$(misl_docs_manifest)
  [[ -f $man ]] || return 1
  awk -v w="$want" '!/^#/ && NF>=5 && ($1==w || $3==w) { print; f=1; exit } END { exit f?0:1 }' "$man"
}

misl_docs_root() {
  local r=${LFS:-/}
  r=${r%/}
  printf '%s\n' "${r:-}"
}

misl_docs_ledger() { printf '%s/var/lib/misl/docs\n' "$(misl_docs_root)"; }

misl_docs_find_archive() {
  local t=$1 p
  for p in "${MISL_DOCS_DIR:-}/$t" "$(misl_docs_root)/usr/src/misl/DOCS/$t"; do
    [[ -n ${p%/"$t"} && -f $p ]] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

# Unpack into $2. tar handles .tar.{gz,bz2,xz}; zip via unzip, bsdtar
# or python3 zipfile (MISL base has python3, not unzip).
misl_docs_unpack() {
  local a=$1 d=$2
  case $a in
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -q "$a" -d "$d" || die "unzip failed: $a"
      elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$a" -C "$d" || die "bsdtar failed: $a"
      elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$a" "$d" || \
          die "python3 zipfile failed: $a"
      else
        die "no unzip, bsdtar or python3 for $a"
      fi
      ;;
    *.tar.*|*.tgz|*.tar)
      tar --no-same-owner --no-same-permissions -xf "$a" -C "$d" || die "tar failed: $a"
      ;;
    *) die "unknown docs archive type: $a" ;;
  esac
}

misl_docs_list() {
  local man name ver tar pkg path state
  man=$(misl_docs_manifest)
  [[ -f $man ]] || die "missing docs manifest: $man"
  printf '%-14s %-10s %-10s %-11s %s\n' NAME VERSION PACKAGE STATE PATH
  while read -r name ver tar pkg path _; do
    [[ -z $name || $name == \#* ]] && continue
    if [[ -f $(misl_docs_ledger)/$name.files ]]; then
      state=installed
    elif misl_docs_find_archive "$tar" >/dev/null; then
      state=available
    else
      state=not-fetched
    fi
    printf '%-14s %-10s %-10s %-11s %s\n' "$name" "$ver" "$pkg" "$state" "$path"
  done < "$man"
  printf 'root=%s archives=%s\n' "$(misl_docs_root)/" "${MISL_DOCS_DIR:-}"
}

misl_docs_install() {
  local want=${1:-} line name tar path root ledger archive tmp base f d n expect
  [[ -n $want ]] || die "usage: misl docs install <name>"
  line=$(misl_docs_row "$want") || die "$want is not in $(misl_docs_manifest)"
  read -r name _ tar _ path _ <<<"$line"
  root=$(misl_docs_root)
  ledger=$(misl_docs_ledger)
  [[ ! -f $ledger/$name.files ]] || { info "already installed $name"; return 0; }
  archive=$(misl_docs_find_archive "$tar") || \
    die "$tar not found in ${MISL_DOCS_DIR:-?} or $root/usr/src/misl/DOCS (MISL_FETCH_DOCS=1 misl sources fetch)"
  if expect=$(misl_md5_for "$tar" 2>/dev/null); then
    [[ $(md5sum "$archive" | awk '{print $1}') == "$expect" ]] || die "HASH-MISMATCH $tar"
  fi

  tmp=$(mktemp -d)
  mkdir "$tmp/x"
  ( misl_docs_unpack "$archive" "$tmp/x" ) || { rm -rf "$tmp"; die "cannot unpack $archive"; }
  # One top-level dir (python-3.14.7-docs-html/, sqlite-doc-.../): strip it.
  base=$tmp/x
  n=$(find "$base" -mindepth 1 -maxdepth 1 | wc -l)
  if (( n == 1 )) && [[ -d $(find "$base" -mindepth 1 -maxdepth 1) ]]; then
    base=$(find "$base" -mindepth 1 -maxdepth 1)
  fi
  chmod -R u+rwX,go+rX,go-w "$base"

  (cd "$base" && find . -mindepth 1 ! -type d | sed 's|^\./||' | LC_ALL=C sort) >"$tmp/files"
  [[ -s $tmp/files ]] || die "$tar is empty"
  while IFS= read -r f; do
    if [[ -e $root$path/$f || -L $root$path/$f ]]; then
      rm -rf "$tmp"
      die "refusing to overwrite $path/$f (not owned by $name)"
    fi
  done <"$tmp/files"

  # Dirs this install creates (deepest first on remove).
  : >"$tmp/dirs"
  d=$path
  while [[ -n $d && $d != / && ! -d $root$d ]]; do
    printf '%s\n' "$d" >>"$tmp/dirs"
    d=$(dirname "$d")
  done
  (cd "$base" && find . -mindepth 1 -type d | sed 's|^\./||') | while IFS= read -r f; do
    [[ -d $root$path/$f ]] || printf '%s\n' "$path/$f"
  done >>"$tmp/dirs"

  mkdir -p "$ledger" "$root$path"
  (cd "$base" && tar -cf - .) | tar --no-same-owner -xf - -C "$root$path"
  sed "s|^|$path/|" "$tmp/files" >"$ledger/$name.files"
  cp "$tmp/dirs" "$ledger/$name.dirs"
  rm -rf "$tmp"
  info "installed $name -> $root$path ($(wc -l <"$ledger/$name.files") files)"
}

misl_docs_remove() {
  local want=${1:-} line name root ledger f
  [[ -n $want ]] || die "usage: misl docs remove <name>"
  line=$(misl_docs_row "$want") || die "$want is not in $(misl_docs_manifest)"
  name=${line%% *}
  root=$(misl_docs_root)
  ledger=$(misl_docs_ledger)
  [[ -f $ledger/$name.files ]] || die "$name is not installed (no $ledger/$name.files)"
  while IFS= read -r f; do
    [[ -n $f ]] && rm -f -- "$root$f"
  done <"$ledger/$name.files"
  if [[ -f $ledger/$name.dirs ]]; then
    awk '{ print length($0) "\t" $0 }' "$ledger/$name.dirs" | sort -rn | cut -f2- | \
      while IFS= read -r f; do
        [[ -n $f ]] && rmdir -- "$root$f" 2>/dev/null || true
      done
  fi
  rm -f -- "$ledger/$name.files" "$ledger/$name.dirs"
  rmdir -- "$ledger" 2>/dev/null || true
  info "removed $name"
}

# 09-config hook: install every MISL_DOCS name. Missing archive = fail.
misl_docs_apply_selected() {
  local n
  for n in ${MISL_DOCS:-}; do
    misl_docs_install "$n"
  done
}

misl_docs() {
  local sub=${1:-list}
  shift || true
  case $sub in
    list) misl_docs_list ;;
    install) misl_docs_install "$@" ;;
    remove) misl_docs_remove "$@" ;;
    *) die "usage: misl docs list|install|remove <name>" ;;
  esac
}
