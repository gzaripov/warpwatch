#!/usr/bin/env bash
#
# Register warpwatch with Codex CLI (~/.codex/hooks.json), merging with any
# existing hooks. Codex fires the same lifecycle as Claude Code:
#   UserPromptSubmit -> start (working)
#   Stop             -> done  (waiting / your turn)
#   PermissionRequest-> input (answer needed)
# (Codex has no SessionEnd, so closed Codex tabs expire via the 7-day prune.)
# The same notify.sh handles it — per-tab keying + warp://session focus come
# from Warp's env, which is present in Codex tabs too. Idempotent + backs up.
set -euo pipefail

NOTIFY="${WARPWATCH_HOME:-$HOME/.claude/warpwatch}/scripts/notify.sh"
HOOKS="$HOME/.codex/hooks.json"
command -v jq >/dev/null || { echo "need jq"; exit 1; }

mkdir -p "$(dirname "$HOOKS")"
[ -f "$HOOKS" ] || echo '{"hooks":{}}' > "$HOOKS"
cp "$HOOKS" "$HOOKS.bak-$(date +%Y%m%d-%H%M%S)"

tmp="$(mktemp)"
jq --arg n "$NOTIFY" '
  def block(arg): {"hooks":[{"type":"command","command":($n + " " + arg + " codex"),"timeout":10}]};
  def merge(ev; arg):
    .hooks[ev] = (((.hooks[ev] // []) | map(select((.hooks[0].command // "") | contains("warpwatch") | not))) + [block(arg)]);
  merge("UserPromptSubmit"; "start")
  | merge("Stop"; "done")
  | merge("PermissionRequest"; "input")
' "$HOOKS" > "$tmp" && mv "$tmp" "$HOOKS"

echo "warpwatch Codex hooks installed in $HOOKS"
