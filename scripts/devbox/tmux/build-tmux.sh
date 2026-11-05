#!/bin/bash
# Build tmux 3.8 with the DevBox patches for the remote (Linux) host.
#
# follow-latest-client-theme.patch: when several terminals are attached to the
# same session and disagree about light and dark (one Mac on a light theme,
# another on a dark one), stock tmux reports whichever client it finds first
# to the panes (mode 2031 / OSC 10 / OSC 11). The patch makes panes follow the
# most recently used terminal (last key press or light/dark switch), and holds
# the 2031 update until that terminal has answered the new background, so an
# application that queries OSC 11 right after the update gets the new colour.
#
# light-panel-tint.patch: a pane background of exactly #f0f0f0 (the fixed panel
# grey of Claude Code's light theme, used behind the user's own messages) is
# drawn with the terminal's ANSI white instead. On an off-white paper page the
# grey is as bright as the page and the panel disappears; DevBox light themes
# define ANSI white as a tint one step darker than the page. Claude Code only
# sends #f0f0f0 inside tmux when CLAUDE_CODE_TMUX_TRUECOLOR=1 (otherwise it
# falls back to 256-colour index 255).
#
# codex-theme-colours.patch: Codex reads the terminal background once at
# startup and fills its composer and the user's messages with that colour
# blended a few percent towards black (light page) or white (dark page), as a
# fixed RGB. It never re-reads it, so after a light/dark switch the panel keeps
# the old shade (a pale bar with unreadable text on a dark page). tmux records
# the backgrounds it reported to each pane (OSC 11) and stores a background that
# matches such a blend as a new theme colour, "themepanel", which every client
# resolves for its own current light or dark (options light-theme-panel,
# default colour7, and dark-theme-panel, default colour0: the DevBox themes
# define those as a shade one step off the page). Codex's diff colours are
# also picked once from the startup background (GitHub-style light or dark
# line and line-number backgrounds, near-black number text on light); they are
# stored as theme colours too (themediffadd, themediffdelete and the -number
# variants, defaulting to Codex's own light and dark values) so each client
# draws the set for its current theme.
#
# Usage: build-tmux.sh <prefix>     (needs libevent-dev, libncurses-dev, bison)
# Then install <prefix>/bin/tmux and restart the tmux server (kill-server);
# a running server keeps the old code.
set -euo pipefail
PREFIX=${1:?usage: build-tmux.sh <prefix>}
VERSION=3.8
SHA256=e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
curl -fsSLo tmux.tar.gz "https://github.com/tmux/tmux/releases/download/$VERSION/tmux-$VERSION.tar.gz"
echo "$SHA256  tmux.tar.gz" | sha256sum -c -
tar xzf tmux.tar.gz
cd "tmux-$VERSION"
patch -p1 < "$HERE/follow-latest-client-theme.patch"
patch -p1 < "$HERE/light-panel-tint.patch"
patch -p1 < "$HERE/codex-theme-colours.patch"
./configure --prefix="$PREFIX"
make -j"$(nproc)"
make install
"$PREFIX/bin/tmux" -V
