#!/usr/bin/env bash
#
# warpwatch — notify.sh
#
# Runs from Claude Code's Stop / Notification hooks. On every agent finish it:
#   1. records the event (epoch, kind, per-tab focus URL, cwd) to a state file
#      so the warpwatch SwiftBar menu-bar item can list recent finishes and let
#      you jump to the EXACT Warp tab the agent ran in;
#   2. plays a sound (afplay — NOT gated by Do Not Disturb);
#   3. optionally pops a notification / dialog / pulls the tab forward.
#
# Focusing is tab-aware via $WARP_FOCUS_URL (the per-session deep link Warp
# injects into every tab), so it always lands on the right tab — never the
# "last" one.
#
# Usage: notify.sh done | input
#
# Env:
#   WARPWATCH_MODE=menubar|notification|dialog|focus|both|silent
#       menubar      (default) record + sound only; the menu-bar item is the UI
#       notification corner banner (uses terminal-notifier if installed)
#       dialog       persistent centre-screen overlay (immune to DND/Focus)
#       focus        jump straight to the agent's tab
#       both         dialog + focus the tab
#       silent       record only — no sound, no popup
#   WARPWATCH_ALWAYS=1        act even when Warp is already frontmost
#   WARPWATCH_DIALOG_GIVEUP   auto-dismiss the dialog after N sec (default 86400)
#   WARPWATCH_SOUND_DONE / WARPWATCH_SOUND_INPUT   custom sounds (.aiff/.wav/.mp3)
#   WARPWATCH_APP=Warp        app to focus when no per-tab URL is available
#   WARPWATCH_STATE=<dir>     state dir (default ~/.claude/warpwatch/state)

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kind="${1:-done}"
app_name="${WARPWATCH_APP:-Warp}"
mode="${WARPWATCH_MODE:-menubar}"
always="${WARPWATCH_ALWAYS:-0}"
giveup="${WARPWATCH_DIALOG_GIVEUP:-86400}"
state_dir="${WARPWATCH_STATE:-$HOME/.claude/warpwatch/state}"

case "$kind" in
  input)
    sound="${WARPWATCH_SOUND_INPUT:-/System/Library/Sounds/Glass.aiff}"
    message="Клод ждёт твоего ответа"
    icon=2 # caution
    ;;
  done | *)
    sound="${WARPWATCH_SOUND_DONE:-/System/Library/Sounds/Hero.aiff}"
    message="Клод закончил"
    icon=1 # note
    ;;
esac

# macOS-only; bail quietly anywhere without osascript.
command -v osascript >/dev/null 2>&1 || exit 0

# Per-tab focus deep link, inherited from the Warp session that launched Claude.
focus_url="${WARP_FOCUS_URL:-}"
if [ -z "$focus_url" ] && [ -n "${WARP_TERMINAL_SESSION_UUID:-}" ]; then
  focus_url="warp://session/$WARP_TERMINAL_SESSION_UUID"
fi

# cwd label — prefer the hook payload's .cwd, fall back to $PWD. Read stdin only
# when piped, so a manual `notify.sh done` in a terminal never hangs.
cwd=""
if [ ! -t 0 ]; then
  payload="$(cat 2>/dev/null || true)"
  cwd="$(printf '%s' "$payload" | /usr/bin/sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -z "$cwd" ] && cwd="$PWD"

# 1) Record the finish for the menu-bar (always; capped to the last 40 lines).
record_finish() {
  mkdir -p "$state_dir" 2>/dev/null || return 0
  local f="$state_dir/finishes.tsv"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$kind" "$focus_url" "$cwd" >> "$f" 2>/dev/null || true
  if [ -f "$f" ]; then
    tail -n 40 "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null || true
  fi
}
record_finish

[ "$mode" = "silent" ] && exit 0

# Guard: stay quiet (no sound/popup) while you're already looking at Warp.
# Compare by bundle id — Warp Stable's process name is "stable", so a name
# match would never fire.
warp_bundle="$(osascript -e "id of app \"$app_name\"" 2>/dev/null)"
if [ "$always" != "1" ]; then
  front_bundle="$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)"
  if [ -n "$front_bundle" ] && [ -n "$warp_bundle" ] && [ "$front_bundle" = "$warp_bundle" ]; then
    exit 0
  fi
fi

# 2) Sound — backgrounded so the hook returns immediately; bypasses DND.
if [ -n "$sound" ] && [ -f "$sound" ] && command -v afplay >/dev/null 2>&1; then
  afplay "$sound" >/dev/null 2>&1 &
fi

# Jump to the exact agent tab (per-tab URL), falling back to plain app activate.
do_focus() {
  if [ -n "$focus_url" ]; then
    open "$focus_url" >/dev/null 2>&1 || true
  else
    osascript -e "tell application \"$app_name\" to activate" >/dev/null 2>&1 || true
  fi
}

# Corner notification. terminal-notifier (if installed) makes the click open the
# exact agent tab; otherwise the built-in display notification (no tab-aware click).
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

# Persistent centre-screen dialog, detached; its button opens the per-tab URL.
show_dialog() {
  nohup osascript "$here/dialog.applescript" "$message" "$app_name" "$icon" "$giveup" "$focus_url" \
    >/dev/null 2>&1 </dev/null &
}

# 3) Optional popup per mode (menubar mode adds nothing beyond sound + record).
case "$mode" in
  notification) do_notification ;;
  dialog) show_dialog ;;
  focus) do_focus ;;
  both) do_focus; show_dialog ;;
  menubar | *) : ;;
esac

exit 0
