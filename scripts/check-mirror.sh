#!/bin/bash
# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# List files from wget-list that are missing on makeitsolinux.org.
# HEAD only — never downloads bodies.
set -euo pipefail

MISL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -n ${MISL_SNAPSHOT:-} ]]; then
  SNAP=$MISL_SNAPSHOT
elif command -v realpath >/dev/null 2>&1; then
  SNAP=$(realpath -m "$MISL_ROOT/../misl-1.0-systemd")
else
  SNAP="$MISL_ROOT/../misl-1.0-systemd"
fi
LIST=${MISL_WGET_LIST:-$SNAP/wget-list}

if [[ $(basename "$LIST") == wget-list.original ]]; then
  echo "refusing wget-list.original" >&2
  exit 2
fi
[[ -f $LIST ]] || { echo "missing $LIST (run: misl sources fetch)" >&2; exit 2; }

ok=0
missing=0
error=0
total=0

while IFS= read -r url || [[ -n $url ]]; do
  url=${url%%#*}
  url=${url//[$'\t\r ']/}
  [[ -n $url ]] || continue
  total=$((total + 1))
  name=${url##*/}
  # HEAD only; -f makes 4xx a failure; do not write a body file.
  code=$(curl -sS -o /dev/null -w '%{http_code}' --head --max-time 20 "$url" || echo 000)
  case $code in
    200|204)
      printf 'OK      %s  %s\n' "$code" "$name"
      ok=$((ok + 1))
      ;;
    301|302|307|308)
      # Follow one redirect with another HEAD.
      final=$(curl -sS -o /dev/null -w '%{http_code}' --head -L --max-time 20 "$url" || echo 000)
      if [[ $final == 200 || $final == 204 ]]; then
        printf 'OK      %s->%s  %s\n' "$code" "$final" "$name"
        ok=$((ok + 1))
      else
        printf 'MISSING %s->%s  %s  %s\n' "$code" "$final" "$name" "$url"
        missing=$((missing + 1))
      fi
      ;;
    404|410)
      printf 'MISSING %s  %s  %s\n' "$code" "$name" "$url"
      missing=$((missing + 1))
      ;;
    *)
      printf 'ERROR   %s  %s  %s\n' "$code" "$name" "$url"
      error=$((error + 1))
      ;;
  esac
done < "$LIST"

printf -- '---\nchecked=%s ok=%s missing=%s error=%s list=%s\n' \
  "$total" "$ok" "$missing" "$error" "$LIST"

if (( missing + error > 0 )); then
  exit 1
fi
exit 0
