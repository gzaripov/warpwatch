#!/usr/bin/env bash
#
# Builds the warpwatch menu-bar state icons as crisp flat vectors (a rounded
# terminal tile; teal = Warp/working, green = done, amber = needs-input, slate =
# idle). Pure vector so it stays sharp at menu-bar size. Requires rsvg-convert.
#
#   build.sh  ──►  idle.png  working.png  done.png  input.png   (36px)
set -euo pipefail
cd "$(dirname "$0")"
command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (brew install librsvg)"; exit 1; }

SIZE=36
render() { rsvg-convert -w "$SIZE" -h "$SIZE" "$1.svg" -o "$1.png" && echo "built $1.png"; }

TILE='<rect x="4" y="4" width="36" height="36" rx="11"'
PROMPT='<path d="M16 16 L24 22 L16 28" fill="none" stroke="%S%" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M27 28 H33" stroke="%S%" stroke-width="3.6" stroke-linecap="round"/>'

cat > idle.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$SIZE" height="$SIZE" viewBox="0 0 44 44">
  $TILE fill="#2C2C31" stroke="#48484E" stroke-width="1.5"/>
  ${PROMPT//%S%/#8A8A90}
</svg>
SVG

cat > working.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$SIZE" height="$SIZE" viewBox="0 0 44 44">
  <defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1ECAD8"/><stop offset="1" stop-color="#0E97A6"/></linearGradient></defs>
  $TILE fill="url(#t)"/>
  ${PROMPT//%S%/#FFFFFF}
</svg>
SVG

cat > done.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$SIZE" height="$SIZE" viewBox="0 0 44 44">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3CD162"/><stop offset="1" stop-color="#27AE49"/></linearGradient></defs>
  $TILE fill="url(#g)"/>
  <path d="M15.5 22.5 L20.5 27.5 L29 17.5" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVG

cat > input.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$SIZE" height="$SIZE" viewBox="0 0 44 44">
  <defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFB740"/><stop offset="1" stop-color="#FF9402"/></linearGradient></defs>
  $TILE fill="url(#a)"/>
  <path d="M22 13 C17 13 13.7 16.4 13.7 21.5 V26 L11 30 H33 L30.3 26 V21.5 C30.3 16.4 27 13 22 13 Z" fill="#fff"/>
  <path d="M18.6 32 H25.4 C25.4 34.1 23.9 35.6 22 35.6 C20.1 35.6 18.6 34.1 18.6 32 Z" fill="#fff"/>
</svg>
SVG

for n in idle working done input; do render "$n"; done
echo done.
