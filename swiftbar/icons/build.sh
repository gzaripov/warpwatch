#!/usr/bin/env bash
#
# Builds the warpwatch menu-bar state icons: the Warp logo as a constant base
# with a bold status badge overlaid (working / done / input). Re-run after
# changing warp-logo.png. Requires rsvg-convert (brew install librsvg).
#
#   warp-logo.png  ──►  idle.png  working.png  done.png  input.png
set -euo pipefail
cd "$(dirname "$0")"

[ -f warp-logo.png ] || { echo "warp-logo.png missing"; exit 1; }
command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (brew install librsvg)"; exit 1; }

LOGO="$(base64 < warp-logo.png | tr -d '\n')"
SIZE=36

emit() { # name  badge-svg  logo-opacity
  local name="$1" badge="$2" op="${3:-1}"
  cat > "$name.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="36" height="36" viewBox="0 0 36 36">
  <image x="1.5" y="1.5" width="33" height="33" opacity="$op" xlink:href="data:image/png;base64,$LOGO"/>
  $badge
</svg>
SVG
  rsvg-convert -w "$SIZE" -h "$SIZE" "$name.svg" -o "$name.png"
  echo "built $name.png"
}

# idle: just the Warp logo, slightly faded (nothing running)
emit idle "" "0.6"

# working: grey badge with a typing dot-trio
emit working '<circle cx="27" cy="27" r="9.4" fill="#ffffff"/><circle cx="27" cy="27" r="7.9" fill="#8A8A8F"/><circle cx="23.6" cy="27" r="1.45" fill="#fff"/><circle cx="27" cy="27" r="1.45" fill="#fff"/><circle cx="30.4" cy="27" r="1.45" fill="#fff"/>'

# done: green badge with a check
emit done '<circle cx="27" cy="27" r="9.4" fill="#ffffff"/><circle cx="27" cy="27" r="7.9" fill="#34C759"/><path d="M23.2 27.3 l2.7 2.7 l4.3 -5.2" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>'

# input: amber badge with an exclamation (it wants you)
emit input '<circle cx="27" cy="27" r="9.4" fill="#ffffff"/><circle cx="27" cy="27" r="7.9" fill="#FF9F0A"/><rect x="25.95" y="22.3" width="2.1" height="6" rx="1.05" fill="#fff"/><circle cx="27" cy="31" r="1.35" fill="#fff"/>'

echo "done."
