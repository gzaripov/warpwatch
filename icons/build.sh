#!/usr/bin/env bash
#
# Builds the warpwatch menu-bar state icons: the official Warp logo mark (white)
# on a rounded tile whose colour = status (slate=idle, teal=working, green=done,
# amber=needs-input). Output is SVG (vector — the plugin feeds it to SwiftBar as
# image=, NSImage scales it crisply) plus an 88px PNG fallback.
#
#   build.sh  ──►  {idle,working,done,input}.svg (+ .png)
set -euo pipefail
cd "$(dirname "$0")"

# Official Warp logo mark (the two panes), bbox ~267×214. Source: warp.dev brand.
MARK='<path d="M136.68 0.549481C136.758 0.227082 137.046 0 137.378 0H237.714C254.047 0 267.288 13.6823 267.288 30.5603V149.206C267.288 166.084 254.047 179.766 237.714 179.766H94.234C93.7688 179.766 93.4263 179.331 93.5357 178.879L136.68 0.549481Z"/><path d="M110.392 34.9425C110.5 34.4908 110.158 34.0565 109.693 34.0565H29.3224C13.1281 34.0565 0 47.7388 0 64.6167V183.262C0 200.14 13.1281 213.823 29.3224 213.823H128.797C129.129 213.823 129.418 213.595 129.495 213.272L133.162 197.984C133.271 197.533 132.928 197.098 132.464 197.098H72.4064C71.9418 197.098 71.5994 196.664 71.7078 196.212L110.392 34.9425Z"/>'

emit() { # name  tile-and-defs-svg  mark-color
  cat > "$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 100 100">
  $2
  <g transform="translate(20,26) scale(0.2245)" fill="$3">$MARK</g>
</svg>
SVG
  echo "wrote $1.svg"
  command -v rsvg-convert >/dev/null && rsvg-convert -w 88 -h 88 "$1.svg" -o "$1.png" || true
}

emit idle \
  '<rect x="6" y="6" width="88" height="88" rx="24" fill="#2C2C31" stroke="#48484E" stroke-width="3"/>' \
  '#8A8A90'

emit working \
  '<defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#27C7D6"/><stop offset="1" stop-color="#0E97A6"/></linearGradient></defs><rect x="6" y="6" width="88" height="88" rx="24" fill="url(#t)"/>' \
  '#ffffff'

emit done \
  '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3CD162"/><stop offset="1" stop-color="#27AE49"/></linearGradient></defs><rect x="6" y="6" width="88" height="88" rx="24" fill="url(#g)"/>' \
  '#ffffff'

emit input \
  '<defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFB740"/><stop offset="1" stop-color="#FF9402"/></linearGradient></defs><rect x="6" y="6" width="88" height="88" rx="24" fill="url(#a)"/>' \
  '#ffffff'

echo done.
