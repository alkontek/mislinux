# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Bootstrap version bump. major.minor only.

misl_version_parse() {
  local v=$1
  [[ $v =~ ^([0-9]+)\.([0-9]+)$ ]] || die "version $v is not major.minor"
  MISL_VER_MAJOR=${BASH_REMATCH[1]}
  MISL_VER_MINOR=${BASH_REMATCH[2]}
}

misl_version_next() {
  local how=${1:-} cur=${MISL_VERSION:?} next
  case $how in
    minor)
      misl_version_parse "$cur"
      next=${MISL_VER_MAJOR}.$((MISL_VER_MINOR + 1))
      ;;
    major)
      misl_version_parse "$cur"
      next=$((MISL_VER_MAJOR + 1)).0
      ;;
    undo|down|revert)
      if [[ -f $MISL_ROOT/VERSION.prev ]]; then
        next=$(tr -d '[:space:]' < "$MISL_ROOT/VERSION.prev")
        misl_version_parse "$next"
      else
        misl_version_parse "$cur"
        (( MISL_VER_MINOR > 0 )) || die "no VERSION.prev; pass an explicit version (misl bump 0.3)"
        next=${MISL_VER_MAJOR}.$((MISL_VER_MINOR - 1))
      fi
      ;;
    [0-9]*.[0-9]*)
      misl_version_parse "$how"
      next=$how
      ;;
    *)
      die "usage: misl bump minor|major|undo|<major.minor> [--codename NAME]"
      ;;
  esac
  printf '%s\n' "$next"
}

misl_conf_set() {
  local file=$1 key=$2 val=$3
  [[ -f $file ]] || return 0
  if grep -q "^${key}=" "$file"; then
    if [[ $val == *[\ \(\"]* ]]; then
      val=${val//\"/}
      sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$file"
    else
      sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    fi
  fi
}

# Optional pretty/codename from docs/../marketing/version_names.txt
misl_codename_for() {
  local ver=$1 line name
  local f=$MISL_ROOT/marketing/version_names.txt
  [[ -f $f ]] || return 0
  line=$(grep -E "^MIS Linux ${ver} \(" "$f" | head -1 || true)
  [[ -n $line ]] || return 0
  name=${line#* (}
  name=${name%%)*}
  printf '%s\n' "${name,,}"
}

misl_bump() {
  local how=${1:-} next pretty code
  shift || true
  local extra_code=
  while [[ $# -gt 0 ]]; do
    case $1 in
      --codename) extra_code=${2:-}; shift 2 ;;
      *) die "usage: misl bump minor|major|<major.minor> [--codename NAME]" ;;
    esac
  done
  [[ -n $how ]] || die "usage: misl bump minor|major|undo|<major.minor> [--codename NAME]"

  next=$(misl_version_next "$how")
  [[ $next != "$MISL_VERSION" ]] || die "already $next"
  pretty="$MISL_NAME $next"
  code=

  if [[ -n $extra_code ]]; then
    code=${extra_code,,}
  elif [[ $next == "${MISL_DIST_VERSION:-1.0}" ]]; then
    code=${MISL_DIST_CODENAME:-farpoint}
  else
    code=$(misl_codename_for "$next" || true)
  fi
  if [[ -n $code ]]; then
    pretty="$MISL_NAME $next ($(misl_codename_display "$code"))"
  fi

  printf '%s\n' "$MISL_VERSION" > "$MISL_ROOT/VERSION.prev"
  printf '%s\n' "$next" > "$MISL_ROOT/VERSION"
  misl_stardate_rotate "$how"
  misl_conf_set "$MISL_ROOT/config/misl.conf" MISL_VERSION "$next"
  misl_conf_set "$MISL_ROOT/config/misl.conf" MISL_VERSION_ID "$next"
  misl_conf_set "$MISL_ROOT/config/misl.conf" MISL_PRETTY_NAME "$pretty"
  misl_conf_set "$MISL_ROOT/config/misl.conf" MISL_VERSION_CODENAME "$code"
  misl_conf_set "$MISL_ROOT/config/misl.conf.example" MISL_VERSION "$next"
  misl_conf_set "$MISL_ROOT/config/misl.conf.example" MISL_VERSION_ID "$next"
  misl_conf_set "$MISL_ROOT/config/misl.conf.example" MISL_PRETTY_NAME "$pretty"
  misl_conf_set "$MISL_ROOT/config/misl.conf.example" MISL_VERSION_CODENAME "$code"

  info "bumped $MISL_VERSION -> $next pretty=$pretty codename=${code:-none}"
  info "stardate $(tr -d '\n' < "$MISL_ROOT/VERSION_STARDATE")"
  info "updated VERSION VERSION_STARDATE config/misl.conf config/misl.conf.example"
  info "re-run misl config apply inside the chroot to refresh /etc/os-release"
}

# Bump records now. Undo swaps VERSION_STARDATE with VERSION_STARDATE.prev.
misl_stardate_rotate() {
  local how=$1 cur_sd= prev_sd=
  local f=$MISL_ROOT/VERSION_STARDATE
  local p=$MISL_ROOT/VERSION_STARDATE.prev
  [[ -f $f ]] && cur_sd=$(tr -d '[:space:]' < "$f")
  [[ -f $p ]] && prev_sd=$(tr -d '[:space:]' < "$p")
  case $how in
    undo|down|revert)
      [[ -n $prev_sd ]] || die "no VERSION_STARDATE.prev to restore"
      printf '%s\n' "$cur_sd" > "$p"
      printf '%s\n' "$prev_sd" > "$f"
      ;;
    *)
      [[ -n $cur_sd ]] && printf '%s\n' "$cur_sd" > "$p"
      misl_stardate_now > "$f"
      ;;
  esac
}

# One TNG-era line from usr/bin/stardate now. Falls back to Kelvin, then raw.
misl_stardate_now() {
  local out line
  [[ -f $MISL_ROOT/usr/bin/stardate ]] || die "missing $MISL_ROOT/usr/bin/stardate"
  out=$(bash "$MISL_ROOT/usr/bin/stardate" now)
  line=$(printf '%s\n' "$out" | awk -F': ' '/TNG Era/{print $2; exit}')
  [[ -n $line ]] || line=$(printf '%s\n' "$out" | awk -F': ' '/Kelvin Era/{print $2; exit}')
  [[ -n $line ]] || line=$(printf '%s\n' "$out" | tail -1)
  printf '%s\n' "$line"
}
