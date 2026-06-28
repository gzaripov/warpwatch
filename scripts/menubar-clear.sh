#!/usr/bin/env bash
# warpwatch — clear the menu-bar dashboard (drops all tracked tabs).
state_dir="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
: > "$state_dir/tabs.tsv" 2>/dev/null || true
