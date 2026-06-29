#!/usr/bin/env bash
#
# warpwatch — focus the exact Warp tab for a session, from the menu-bar.
# Usage: menubar-open.sh <warp-session-uuid>
#
# The tab stays "waiting" until you actually send it a prompt (UserPromptSubmit
# flips it back to working) — opening it doesn't fake-clear the status.
set -uo pipefail
uuid="${1:-}"
[ -n "$uuid" ] || exit 0

state_dir="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
state="$state_dir/tabs.tsv"

url="$(awk -F'\t' -v u="$uuid" '$1==u{print $6; exit}' "$state" 2>/dev/null)"
[ -n "$url" ] && open "$url" >/dev/null 2>&1 || true
