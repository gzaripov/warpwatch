#!/usr/bin/env bash
#
# <xbar.title>warpwatch</xbar.title>
# <xbar.version>v0.2.0</xbar.version>
# <xbar.author>Grigory Zaripov</xbar.author>
# <xbar.author.github>gzaripov</xbar.author.github>
# <xbar.desc>Lists Claude Code agent finishes; click one to jump to the exact Warp tab.</xbar.desc>
# <xbar.dependencies>warp,claude-code</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# warpwatch SwiftBar plugin. Reads the finishes recorded by scripts/notify.sh and
# renders a menu-bar item: a terminal glyph (+ count badge) whose dropdown lists
# recent agent finishes, newest first. Each item runs `open warp://session/<id>`
# to focus the EXACT tab the agent ran in. Immune to Do Not Disturb / Focus.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

STATE_DIR="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
STATE="$STATE_DIR/finishes.tsv"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAR="$HERE/../scripts/menubar-clear.sh"

count=0
[ -f "$STATE" ] && count="$(grep -c . "$STATE" 2>/dev/null || echo 0)"

# --- menu bar item ---
if [ "$count" -gt 0 ]; then
  echo "$count | sfimage=terminal.fill"
else
  echo "| sfimage=terminal"
fi

echo "---"
if [ "$count" -gt 0 ] && [ -f "$STATE" ]; then
  now="$(date +%s)"
  # newest first
  tail -r "$STATE" 2>/dev/null | while IFS=$'\t' read -r epoch kind url cwd; do
    [ -n "$url" ] || continue
    label="$(basename "$cwd" 2>/dev/null)"; [ -n "$label" ] || label="warp"
    diff=$(( now - epoch ))
    if   [ "$diff" -lt 60 ];    then rel="${diff}s ago"
    elif [ "$diff" -lt 3600 ];  then rel="$(( diff / 60 ))m ago"
    elif [ "$diff" -lt 86400 ]; then rel="$(( diff / 3600 ))h ago"
    else                             rel="$(( diff / 86400 ))d ago"
    fi
    glyph="✅"; [ "$kind" = "input" ] && glyph="⌨️"
    echo "$glyph $label · $rel | shell=/usr/bin/open param1=$url terminal=false"
  done
  echo "---"
  echo "Очистить список | shell=$CLEAR terminal=false refresh=true"
else
  echo "Нет недавних агентов | color=gray"
fi
echo "---"
echo "Открыть Warp | shell=/usr/bin/open param1=-a param2=Warp terminal=false"
