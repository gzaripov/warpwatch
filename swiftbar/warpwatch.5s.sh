#!/usr/bin/env bash
#
# <xbar.title>warpwatch</xbar.title>
# <xbar.version>v0.3.0</xbar.version>
# <xbar.author>Grigory Zaripov</xbar.author>
# <xbar.author.github>gzaripov</xbar.author.github>
# <xbar.desc>Per-tab dashboard of Claude Code agents in Warp; click a tab to jump to it.</xbar.desc>
# <xbar.dependencies>warp,claude-code</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Reads the per-tab dashboard maintained by scripts/notify.sh and renders a
# menu-bar item: one row per Warp tab with its name + live status. The icon is
# dim/grey while everything is just working, and lights up bright when a tab has
# finished or needs your input. Click a row to jump to that exact tab.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

STATE_DIR="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
STATE="$STATE_DIR/tabs.tsv"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN="$HERE/../scripts/menubar-open.sh"
CLEAR="$HERE/../scripts/menubar-clear.sh"

now="$(date +%s)"
attention=0; working=0; total=0
if [ -f "$STATE" ]; then
  attention="$(awk -F'\t' '$2=="done"||$2=="input"{c++} END{print c+0}' "$STATE")"
  working="$(awk -F'\t' '$2=="working"{c++} END{print c+0}' "$STATE")"
  total="$(grep -c . "$STATE" 2>/dev/null || echo 0)"
fi

# --- menu bar item: bright on attention, dim otherwise ---
if [ "$attention" -gt 0 ]; then
  echo "$attention | sfimage=bell.badge.fill sfcolor=orange"
elif [ "$working" -gt 0 ]; then
  echo "| sfimage=hourglass sfcolor=gray"
else
  echo "| sfimage=terminal sfcolor=gray"
fi

echo "---"
if [ "$total" -gt 0 ]; then
  echo "Warp agents | size=11 color=gray"
  # order: input, then done, then working, then seen; newest within each group
  awk -F'\t' '
    function rank(s){ if(s=="input")return 0; if(s=="done")return 1; if(s=="working")return 2; return 3 }
    NF>=6 { printf "%d\t%d\t%s\n", rank($2), -$3, $0 }
  ' "$STATE" | sort -t"$(printf '\t')" -k1,1n -k2,2n | cut -f3- | while IFS=$'\t' read -r uuid status epoch name cwd url; do
    [ -n "$uuid" ] || continue
    case "$status" in
      input)   g="⌨️"; col="orange" ;;
      done)    g="✅"; col="green" ;;
      working) g="⏳"; col="gray" ;;
      *)       g="•";  col="gray" ;;
    esac
    d=$(( now - epoch ))
    if   [ "$d" -lt 60 ];    then rel="${d}s"
    elif [ "$d" -lt 3600 ];  then rel="$(( d / 60 ))m"
    elif [ "$d" -lt 86400 ]; then rel="$(( d / 3600 ))h"
    else                          rel="$(( d / 86400 ))d"
    fi
    [ -n "$name" ] || name="warp"
    echo "$g $name · $rel | color=$col shell=$OPEN param1=$uuid terminal=false refresh=true"
  done
  echo "---"
  echo "Очистить | shell=$CLEAR terminal=false refresh=true"
else
  echo "Нет активных вкладок | color=gray"
fi
echo "---"
echo "Открыть Warp | shell=/usr/bin/open param1=-a param2=Warp terminal=false"
