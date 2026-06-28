#!/usr/bin/env bash
#
# warpwatch installer. Makes the scripts executable, creates the state dir, and
# prints the two manual steps (settings.json hooks + SwiftBar). Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "$ROOT"/scripts/*.sh "$ROOT"/swiftbar/*.sh 2>/dev/null || true
mkdir -p "$HOME/.claude/warpwatch/state"

cat <<EOF
warpwatch files are ready at:
  $ROOT

── 1. Hooks ─────────────────────────────────────────────────────────────────
Merge into ~/.claude/settings.json (keep any existing "hooks"):

  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "\"$ROOT/scripts/notify.sh\" start", "timeout": 10 } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "\"$ROOT/scripts/notify.sh\" done",  "timeout": 10 } ] } ],
    "Notification":     [ { "hooks": [ { "type": "command", "command": "\"$ROOT/scripts/notify.sh\" input", "timeout": 10 } ] } ],
    "SessionEnd":       [ { "hooks": [ { "type": "command", "command": "\"$ROOT/scripts/notify.sh\" end",   "timeout": 10 } ] } ]
  }

── 2. Menu-bar item (SwiftBar) ──────────────────────────────────────────────
  brew install --cask swiftbar
  defaults write com.ameba.SwiftBar PluginDirectory "$ROOT/swiftbar"
  open -a SwiftBar

Optional: brew install terminal-notifier   (clickable corner notifications)
EOF
