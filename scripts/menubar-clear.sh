#!/usr/bin/env bash
# warpwatch — clear the menu-bar inbox of recent agent finishes.
state_dir="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
: > "$state_dir/finishes.tsv" 2>/dev/null || true
