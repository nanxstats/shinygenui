#!/bin/bash

set -euo pipefail

LOGO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$LOGO_DIR/../.." && pwd)"
PATTERN_HTML="$LOGO_DIR/logo-pattern.html"
PATTERN_PNG="$LOGO_DIR/logo-pattern.png"
TEXT_SVG="$LOGO_DIR/logo-text.svg"
TEXT_PDF="$LOGO_DIR/logo-text.pdf"
TEXT_PNG="$LOGO_DIR/logo-text.png"
OUTPUT_PNG="$PACKAGE_ROOT/man/figures/logo.png"

if [[ "$OSTYPE" == "darwin"* ]]; then
    CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    CHROME_BIN="/c/Program Files/Google/Chrome/Application/chrome.exe"
else
    CHROME_BIN="/usr/bin/google-chrome"
fi

if [ ! -f "$CHROME_BIN" ]; then
    echo "Chrome/Chromium not found at $CHROME_BIN"
    exit 1
fi

# Render the deterministic p5.brush field at 2x the final logo resolution.
"$CHROME_BIN" --headless \
    --enable-gpu \
    --disable-software-rasterizer \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size=1106,1280 \
    --virtual-time-budget=10000 \
    --screenshot="$PATTERN_PNG" \
    "file://$PATTERN_HTML"

# Chrome can exit successfully even when WebGL initialization fails. A failed
# capture is nearly monochrome, whereas the rendered field contains thousands
# of subtly different watercolor and brush colors.
PATTERN_COLORS="$(magick "$PATTERN_PNG" -format %k info:)"
if (( PATTERN_COLORS < 500 )); then
    echo "Pattern render is incomplete ($PATTERN_COLORS colors); check Chrome WebGL and CDN access."
    exit 1
fi

# Clip the rendered field to the sticker and add a bold poppy-red border.
magick "$PATTERN_PNG" \
    -resize 553x640! \
    \( -size 553x640 xc:black \
        -fill white \
        -draw "polygon 276.5,7 547,163 547,477 276.5,633 6,477 6,163" \) \
    -alpha off -compose CopyOpacity -composite \
    -fill none \
    -stroke "#386769" -strokewidth 11 \
    -draw "polygon 276.5,7 547,163 547,477 276.5,633 6,477 6,163" \
    "$OUTPUT_PNG"

# Generate the wordmark and compose it with the background. This avoids the
# limited ligature support in hexSticker and ImageMagick.

"$CHROME_BIN" --headless \
    --disable-gpu \
    --no-margins \
    --no-pdf-header-footer \
    --print-to-pdf="$TEXT_PDF" \
    "$TEXT_SVG"

pdfcrop --quiet \
    "$TEXT_PDF" "$TEXT_PDF"

magick -density 2000 "$TEXT_PDF" \
    -resize 25% \
    -alpha set -background none -channel A \
    -evaluate multiply 1.3 +channel \
    -transparent white \
    "$TEXT_PNG"

magick "$OUTPUT_PNG" "$TEXT_PNG" \
    -gravity center \
    -geometry +0-0 \
    -composite "$OUTPUT_PNG"

rm "$TEXT_PDF" "$TEXT_PNG"

# Optimize PNG
pngquant "$OUTPUT_PNG" \
    --force \
    --output "$OUTPUT_PNG"
