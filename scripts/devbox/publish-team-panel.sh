#!/usr/bin/env bash
# Publishes the DevBox team panel script on the devbox, where cmux DevBox
# (112.41+) fetches it over SSH while the panel is shown, so panel-only
# changes reach every Mac without an app release (see
# Sources/DevBoxTeamPanelSource.swift).
#
# Run on the devbox from the repo checkout. Refuses uncommitted panel changes
# and a `rev` that is not higher than the published one; the app also ignores
# a copy whose `min-build` is newer than itself.
#
#   scripts/devbox/publish-team-panel.sh [--dry-run]
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
src="$repo/Resources/devbox-sidebars/devbox.js"
dest="$HOME/.local/share/cmux-devbox/panel/devbox.js"

header_field() { # <file> <field>
  head -n 1 "$1" | grep -E '^// cmux-devbox-panel ' | tr ' ' '\n' | sed -n "s/^$2=//p"
}

rev="$(header_field "$src" rev)"
min_build="$(header_field "$src" min-build)"
[[ "$rev" =~ ^[0-9]+$ && "$min_build" =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
  echo "error: line 1 of $src must be '// cmux-devbox-panel rev=<n> min-build=<build>'" >&2; exit 1; }

if ! git -C "$repo" diff --quiet HEAD -- "$src"; then
  echo "error: commit the panel change first ($src has uncommitted edits)" >&2; exit 1
fi

if [[ -f "$dest" ]]; then
  published="$(header_field "$dest" rev || true)"
  if [[ -n "$published" && "$rev" -le "$published" ]]; then
    if cmp -s "$src" "$dest"; then echo "already published: rev=$rev"; exit 0; fi
    echo "error: rev=$rev is not higher than the published rev=$published; bump line 1" >&2; exit 1
  fi
fi

if command -v node >/dev/null 2>&1; then
  node --check "$src"
fi

if [[ "${1:-}" == --dry-run ]]; then
  echo "would publish rev=$rev min-build=$min_build to $dest"; exit 0
fi

mkdir -p "$(dirname "$dest")"
tmp="$(mktemp "$dest.XXXXXX")"
cp "$src" "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$dest"
echo "published rev=$rev min-build=$min_build ($(git -C "$repo" log -1 --format=%h -- "$src")) → $dest"
