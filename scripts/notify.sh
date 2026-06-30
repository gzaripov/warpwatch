#!/usr/bin/env bash
#
# warpwatch — notify.sh   (actions: start | done | input | end)
#
# Maintains a per-Warp-tab dashboard: one row per tab, keyed by the Warp session
# UUID, so the warpwatch menu-bar item can show each tab's NAME and live STATUS
# (working / finished / needs-input) and light up when a tab wants you. Focusing
# a tab uses its own warp://session deep link — always the right tab.
#
#   UserPromptSubmit -> start  (tab is now working; name = your prompt)
#   Stop             -> done   (tab finished — needs attention)
#   Notification     -> input  (tab needs your input — needs attention)
#   SessionEnd       -> end    (drop the tab from the dashboard)
#
# State row (TSV): uuid \t status \t epoch \t name \t cwd \t focus_url
#
# Env:
#   WARPWATCH_MODE=menubar|notification|dialog|focus|both|silent   (default menubar)
#   WARPWATCH_ALWAYS=1        act even when Warp is already frontmost
#   WARPWATCH_SOUND_DONE / WARPWATCH_SOUND_INPUT                    custom sounds
#   WARPWATCH_DIALOG_GIVEUP   auto-dismiss the dialog after N sec (default 86400)
#   WARPWATCH_APP=Warp        app to focus when no per-tab URL is available
#   WARPWATCH_STATE=<dir>     state dir (default ~/.claude/warpwatch/state)

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

action="${1:-done}"
app_name="${WARPWATCH_APP:-Warp}"
mode="${WARPWATCH_MODE:-menubar}"
always="${WARPWATCH_ALWAYS:-0}"
giveup="${WARPWATCH_DIALOG_GIVEUP:-86400}"
state_dir="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"
state="$state_dir/tabs.tsv"

# macOS-only.
command -v osascript >/dev/null 2>&1 || exit 0

uuid="${WARP_TERMINAL_SESSION_UUID:-}"
focus_url="${WARP_FOCUS_URL:-}"
[ -z "$focus_url" ] && [ -n "$uuid" ] && focus_url="warp://session/$uuid"

# stdin payload (only when piped) -> cwd, prompt. Never block on a real tty.
payload=""
[ ! -t 0 ] && payload="$(cat 2>/dev/null || true)"
jget() { [ -n "$payload" ] && printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
cwd="$(jget '.cwd')"; [ -z "$cwd" ] && cwd="$PWD"
prompt="$(jget '.prompt')"
transcript="$(jget '.transcript_path')"
agent="$(printf '%s' "${2:-claude}" | tr 'A-Z' 'a-z' | tr -cd 'a-z')"; [ -z "$agent" ] && agent="claude"

sanitize() { printf '%s' "$1" | tr '\t\n\r' '   ' | tr -s ' ' | sed 's/^ *//;s/ *$//'; }
now="$(date +%s)"

# Claude's AI-generated chat name (latest "ai-title" in the transcript) — the
# meaningful session title; preferred over the raw prompt for the tab label.
chat_name=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  chat_name="$(sanitize "$(grep '"type":"ai-title"' "$transcript" 2>/dev/null | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null)" | cut -c1-48)"
fi

lookup() { # column-index -> value for the current uuid
  [ -f "$state" ] && awk -F'\t' -v u="$uuid" -v c="$1" '$1==u{print $c; exit}' "$state"
}

# tab label: chat title -> prompt -> previous name -> cwd basename
derive_name() {
  local n="$chat_name"
  [ -z "$n" ] && n="$(sanitize "$prompt" | cut -c1-48)"
  [ -z "$n" ] && n="$(lookup 4)"
  [ -z "$n" ] && n="$(basename "$cwd")"
  printf '%s' "$n"
}

write_tab() { # status name
  local status="$1" name="$2" tmp="$state.$$"
  mkdir -p "$state_dir" 2>/dev/null || return 0
  if [ -f "$state" ]; then
    awk -F'\t' -v u="$uuid" -v now="$now" 'NF>=6 && $1!=u && (now-$3)<604800' "$state" > "$tmp" 2>/dev/null || : > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$uuid" "$status" "$now" "$name" "$cwd" "$focus_url" "$agent" >> "$tmp"
  tail -n 40 "$tmp" > "$state" 2>/dev/null && rm -f "$tmp" || mv "$tmp" "$state" 2>/dev/null || true
}

remove_tab() {
  [ -f "$state" ] || return 0
  local tmp="$state.$$"
  awk -F'\t' -v u="$uuid" 'NF>=6 && $1!=u' "$state" > "$tmp" 2>/dev/null && mv "$tmp" "$state" 2>/dev/null || rm -f "$tmp"
}

# Per-tab tracking needs a Warp UUID. Without it we still do sound on done/input.
if [ -n "$uuid" ]; then
  case "$action" in
    start)
      write_tab working "$(derive_name)"
      exit 0
      ;;
    end)
      remove_tab
      exit 0
      ;;
    done | input)
      # both mean "the agent stopped — your turn" (finished a turn or asked
      # a question). One state: waiting.
      write_tab waiting "$(derive_name)"
      ;;
  esac
fi

# start/end never make noise.
case "$action" in start | end) exit 0 ;; esac
[ "$mode" = "silent" ] && exit 0

case "$action" in
  input) sound="${WARPWATCH_SOUND_INPUT:-/System/Library/Sounds/Glass.aiff}"; message="Agent is waiting for your input"; icon=2 ;;
  *)     sound="${WARPWATCH_SOUND_DONE:-/System/Library/Sounds/Hero.aiff}";  message="Agent finished";                icon=1 ;;
esac

# Guard: stay quiet (no sound/popup) while you're already looking at Warp.
warp_bundle="$(osascript -e "id of app \"$app_name\"" 2>/dev/null)"
if [ "$always" != "1" ]; then
  front_bundle="$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)"
  if [ -n "$front_bundle" ] && [ -n "$warp_bundle" ] && [ "$front_bundle" = "$warp_bundle" ]; then
    exit 0
  fi
fi

# Sound — backgrounded; bypasses Do Not Disturb.
if [ -n "$sound" ] && [ -f "$sound" ] && command -v afplay >/dev/null 2>&1; then
  afplay "$sound" >/dev/null 2>&1 &
fi

do_focus() {
  if [ -n "$focus_url" ]; then open "$focus_url" >/dev/null 2>&1 || true
  else osascript -e "tell application \"$app_name\" to activate" >/dev/null 2>&1 || true; fi
}
do_notification() {
  if command -v terminal-notifier >/dev/null 2>&1; then
    if [ -n "$focus_url" ]; then
      terminal-notifier -title "Claude Code" -message "$message" -execute "open '$focus_url'" >/dev/null 2>&1 || true
    else
      terminal-notifier -title "Claude Code" -message "$message" >/dev/null 2>&1 || true
    fi
  else
    osascript -e "display notification \"$message\" with title \"Claude Code\"" >/dev/null 2>&1 || true
  fi
}
show_dialog() {
  nohup osascript "$here/dialog.applescript" "$message" "$app_name" "$icon" "$giveup" "$focus_url" >/dev/null 2>&1 </dev/null &
}

case "$mode" in
  notification) do_notification ;;
  dialog) show_dialog ;;
  focus) do_focus ;;
  both) do_focus; show_dialog ;;
  menubar | *) : ;;
esac
exit 0
