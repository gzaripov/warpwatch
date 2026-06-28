#!/usr/bin/env bash
#
# warpwatch — open a tab from the menu-bar and clear its "needs attention" flag.
# Usage: menubar-open.sh <warp-session-uuid>
set -uo pipefail
uuid="${1:-}"
[ -n "$uuid" ] || exit 0

state_dir="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
state="$state_dir/tabs.tsv"

# Focus the exact tab via its deep link.
url="$(awk -F'\t' -v u="$uuid" '$1==u{print $6; exit}' "$state" 2>/dev/null)"
[ -n "$url" ] && open "$url" >/dev/null 2>&1 || true

# done/input -> seen, so the menu-bar icon calms down (the row stays listed).
if [ -f "$state" ]; then
  tmp="$state.$$"
  awk -F'\t' -v u="$uuid" 'BEGIN{OFS="\t"} {if($1==u && ($2=="done"||$2=="input")) $2="seen"; print}' "$state" > "$tmp" 2>/dev/null \
    && mv "$tmp" "$state" 2>/dev/null || rm -f "$tmp"
fi
