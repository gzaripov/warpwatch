#!/usr/bin/env bash
#
# Build the app and install a LaunchAgent so it starts at login and stays
# running. Safe to re-run (rebuilds + reloads).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
APP="$(pwd)/WarpwatchBar.app"
EXE="$APP/Contents/MacOS/warpwatch-bar"
PLIST="$HOME/Library/LaunchAgents/com.gzaripov.warpwatch.plist"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.gzaripov.warpwatch</string>
  <key>ProgramArguments</key><array><string>$EXE</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$HOME/.claude/warpwatch/state/warpwatch.log</string>
  <key>StandardErrorPath</key><string>$HOME/.claude/warpwatch/state/warpwatch.log</string>
</dict>
</plist>
PLISTEOF

DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/com.gzaripov.warpwatch" 2>/dev/null || true
pkill -f 'WarpwatchBar.app' 2>/dev/null || true
# bootstrap can momentarily I/O-error mid-teardown; fall back to load/kickstart.
launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null \
  || launchctl load -w "$PLIST" 2>/dev/null \
  || launchctl kickstart -k "$DOMAIN/com.gzaripov.warpwatch" 2>/dev/null \
  || true
echo "installed + started — LaunchAgent: $PLIST"
