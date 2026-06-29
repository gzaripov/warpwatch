#!/usr/bin/env bash
#
# <xbar.title>warpwatch</xbar.title>
# <xbar.version>v0.6.0</xbar.version>
# <xbar.author>Grigory Zaripov</xbar.author>
# <xbar.author.github>gzaripov</xbar.author.github>
# <xbar.desc>Per-tab dashboard of Claude Code agents in Warp; click a tab to jump to it.</xbar.desc>
# <xbar.dependencies>warp,claude-code</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Menu-bar item = the Warp logo with a status badge (idle / working / done /
# input), so it's clearly Warp and you can tell the state at a glance. The
# dropdown lists each Warp tab with its name + status; click a row to jump to
# that exact tab.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

STATE_DIR="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
STATE="$STATE_DIR/tabs.tsv"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Assets live OUTSIDE the SwiftBar plugin folder — SwiftBar runs every file in
# its plugin dir as a plugin, so icons must not sit next to this script.
ICONS="$HERE/../icons"
OPEN="$HERE/../scripts/menubar-open.sh"
CLEAR="$HERE/../scripts/menubar-clear.sh"

now="$(date +%s)"
waiting=0; working=0; total=0
if [ -f "$STATE" ]; then
  # "waiting" = the agent stopped and it's your turn (any non-working row,
  # so legacy done/input/seen rows are treated as waiting too).
  waiting="$(awk -F'\t' 'NF>=6 && $2!="working"{c++} END{print c+0}' "$STATE")"
  working="$(awk -F'\t' 'NF>=6 && $2=="working"{c++} END{print c+0}' "$STATE")"
  total="$(grep -c . "$STATE" 2>/dev/null || echo 0)"
fi
attention=$waiting

# menu-bar state: waiting (your turn) > working > idle
state="idle"
if   [ "$waiting" -gt 0 ]; then state="waiting"
elif [ "$working" -gt 0 ]; then state="working"
fi

# --- menu bar item: Warp logo, tile colour = status (vector SVG, crisp at any size) ---
icon="$ICONS/$state.svg"
if [ -f "$icon" ]; then
  b64="$(base64 < "$icon" | tr -d '\n')"
  if [ "$attention" -gt 0 ]; then
    echo "$attention | image=$b64"
  else
    echo "| image=$b64"
  fi
else
  # fallback to SF Symbols if the rendered icons aren't present
  if [ "$attention" -gt 0 ]; then echo "$attention | sfimage=bell.badge.fill sfcolor=orange"
  else echo "| sfimage=terminal sfcolor=gray"; fi
fi

echo "---"
if [ "$total" -gt 0 ]; then
  echo "Warp agents | size=11"
  awk -F'\t' '
    function rank(s){ return (s=="working") ? 1 : 0 }
    NF>=6 { printf "%d\t%d\t%s\n", rank($2), -$3, $0 }
  ' "$STATE" | sort -t"$(printf '\t')" -k1,1n -k2,2n | cut -f3- | while IFS=$'\t' read -r uuid status epoch name cwd url; do
    [ -n "$uuid" ] || continue
    # ⏳ = agent working, 💬 = stopped and waiting for you. Colourful emoji are
    # self-coloured, so they stay vivid + legible on the native menu background.
    case "$status" in
      working) g="⏳" ;;
      *)       g="💬" ;;
    esac
    d=$(( now - epoch ))
    if   [ "$d" -lt 60 ];    then rel="${d}s"
    elif [ "$d" -lt 3600 ];  then rel="$(( d / 60 ))m"
    elif [ "$d" -lt 86400 ]; then rel="$(( d / 3600 ))h"
    else                          rel="$(( d / 86400 ))d"
    fi
    [ -n "$name" ] || name="warp"
    echo "$g $name · $rel | shell=$OPEN param1=$uuid terminal=false refresh=true"
  done
  echo "---"
  echo "Очистить | shell=$CLEAR terminal=false refresh=true"
else
  echo "Нет активных вкладок | color=#98989F"
fi
echo "---"
echo "Открыть Warp | shell=/usr/bin/open param1=-a param2=Warp terminal=false"
