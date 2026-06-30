#!/usr/bin/env bash
#
# <xbar.title>warpwatch</xbar.title>
# <xbar.version>v0.7.0</xbar.version>
# <xbar.author>Grigory Zaripov</xbar.author>
# <xbar.author.github>gzaripov</xbar.author.github>
# <xbar.desc>Per-tab dashboard of Claude Code agents in Warp; click a tab to jump to it.</xbar.desc>
# <xbar.dependencies>warp,claude-code</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Streaming plugin: stays alive and emits a fresh menu separated by "~~~".
# While a tab is waiting, the menu-bar Warp icon gently PULSES to get your
# attention; when nothing's waiting it just refreshes slowly (low CPU). The
# dropdown is cached between state reads so only the small bar icon is rebuilt
# each animation frame. Set WARPWATCH_PULSE=0 to disable the animation.
#
# Menu-bar icon = Warp logo on a status-coloured tile (teal=working,
# amber=waiting). Dropdown = one row per tab with a coloured status dot.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

STATE_DIR="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
STATE="$STATE_DIR/tabs.tsv"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONS="$HERE/../icons"
OPEN="$HERE/../scripts/menubar-open.sh"
PULSE="${WARPWATCH_PULSE:-1}"

# Official Warp logo mark (two panes) — used to build the pulsing amber icon.
MARK='<path d="M136.68 0.549481C136.758 0.227082 137.046 0 137.378 0H237.714C254.047 0 267.288 13.6823 267.288 30.5603V149.206C267.288 166.084 254.047 179.766 237.714 179.766H94.234C93.7688 179.766 93.4263 179.331 93.5357 178.879L136.68 0.549481Z"/><path d="M110.392 34.9425C110.5 34.4908 110.158 34.0565 109.693 34.0565H29.3224C13.1281 34.0565 0 47.7388 0 64.6167V183.262C0 200.14 13.1281 213.823 29.3224 213.823H128.797C129.129 213.823 129.418 213.595 129.495 213.272L133.162 197.984C133.271 197.533 132.928 197.098 132.464 197.098H72.4064C71.9418 197.098 71.5994 196.664 71.7078 196.212L110.392 34.9425Z"/>'

waiting_b64() { # $1 = opacity (pulse frame)
  printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 100 100"><g opacity="'"$1"'"><defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFB740"/><stop offset="1" stop-color="#FF9402"/></linearGradient></defs><rect x="15" y="15" width="70" height="70" rx="18" fill="url(#a)"/><g transform="translate(29,33.2) scale(0.157)" fill="#ffffff">'"$MARK"'</g></g></svg>' | base64 | tr -d '\n'
}

# read the dashboard state -> globals: waiting working total attention state
read_state() {
  now="$(date +%s)"
  waiting=0; working=0; total=0
  if [ -f "$STATE" ]; then
    waiting="$(awk -F'\t' 'NF>=6 && $2!="working"{c++} END{print c+0}' "$STATE")"
    working="$(awk -F'\t' 'NF>=6 && $2=="working"{c++} END{print c+0}' "$STATE")"
    total="$(grep -c . "$STATE" 2>/dev/null || echo 0)"
  fi
  attention=$waiting
  state="idle"
  if   [ "$waiting" -gt 0 ]; then state="waiting"
  elif [ "$working" -gt 0 ]; then state="working"; fi
}

# build the dropdown (everything below the menu-bar line) -> echoes text
build_dropdown() {
  echo "---"
  if [ "$total" -gt 0 ]; then
    echo "Warp agents | size=11"
    awk -F'\t' '
      function rank(s){ return (s=="working") ? 1 : 0 }
      NF>=6 { printf "%d\t%d\t%s\n", rank($2), -$3, $0 }
    ' "$STATE" | sort -t"$(printf '\t')" -k1,1n -k2,2n | cut -f3- | while IFS=$'\t' read -r uuid status epoch name cwd url; do
      [ -n "$uuid" ] || continue
      case "$status" in
        working) ricon="$ICONS/row-working.svg" ; tip="Agent is working" ;;
        *)       ricon="$ICONS/row-waiting.svg" ; tip="Agent is waiting for your input" ;;
      esac
      rb64="$(base64 < "$ricon" 2>/dev/null | tr -d '\n')"
      d=$(( now - epoch ))
      if   [ "$d" -lt 60 ];    then rel="${d}s"
      elif [ "$d" -lt 3600 ];  then rel="$(( d / 60 ))m"
      elif [ "$d" -lt 86400 ]; then rel="$(( d / 3600 ))h"
      else                          rel="$(( d / 86400 ))d"
      fi
      [ -n "$name" ] || name="warp"
      echo "$name · $rel | image=$rb64 tooltip=\"$tip\" shell=$OPEN param1=$uuid terminal=false refresh=true"
    done
  else
    echo "No active agents | color=#98989F"
  fi
  echo "---"
  echo "Open Warp | shell=/usr/bin/open param1=-a param2=Warp terminal=false"
}

# emit the menu-bar line for the current state at pulse-opacity $1
bar_line() {
  local b64
  if [ "$state" = "waiting" ] && [ "$PULSE" = "1" ]; then
    b64="$(waiting_b64 "$1")"
  else
    b64="$(base64 < "$ICONS/$state.svg" 2>/dev/null | tr -d '\n')"
  fi
  if [ "$attention" -gt 0 ]; then
    echo "$attention | image=$b64 tooltip=\"warpwatch — $waiting waiting, $working working\""
  else
    echo "| image=$b64 tooltip=\"warpwatch — $waiting waiting, $working working\""
  fi
}

ops=(1.0 0.82 0.62 0.5 0.62 0.82)
f=0
last_read=0
dropdown=""
while :; do
  t="$(date +%s)"
  if [ -z "$dropdown" ] || [ "$(( t - last_read ))" -ge 2 ]; then
    read_state
    dropdown="$(build_dropdown)"
    last_read="$t"
  fi
  bar_line "${ops[$f]}"
  printf '%s\n' "$dropdown"
  echo "~~~"
  if [ "$PULSE" = "1" ] && [ "${attention:-0}" -gt 0 ]; then
    f=$(( (f + 1) % 6 )); sleep 0.16
  else
    f=0; sleep 1.5
  fi
done
