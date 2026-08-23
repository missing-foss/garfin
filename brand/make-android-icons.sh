#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Renders the Android launcher icons from brand/svg/. Run from inside brand/:
#   ./make-android-icons.sh
#
# The PNGs it writes are generated artwork, not source: this script is the
# source. Re-run it after any change to garfin-icon-{foreground,background}.svg
# rather than editing the output.
#
# Needs rsvg-convert (librsvg2-bin). Deliberately not ImageMagick: the legacy
# icon is composited by building one SVG rather than by flattening two PNGs,
# so there is no second rasteriser to disagree about gamma or antialiasing.
#
# The wordmark is NOT involved here — the icon carries the mark alone — so this
# does not depend on outline.sh or on Fredoka being installed. Anything that
# rasterises the wordmark does.
set -euo pipefail

cd "$(dirname "$0")"
res="../android/app/src/main/res"
fg="svg/garfin-icon-foreground.svg"
bg="svg/garfin-icon-background.svg"

command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (librsvg2-bin)"; exit 1; }

# Adaptive foreground: the full 108dp canvas, art inside the 66dp safe zone.
# Android crops and masks this itself, so it must not be pre-cropped.
for d in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density="${d%%:*}"; px="${d##*:}"
  mkdir -p "$res/mipmap-$density"
  rsvg-convert -w "$px" -h "$px" "$fg" -o "$res/mipmap-$density/ic_launcher_foreground.png"
done

# Legacy square icon, for launchers that ask for the pre-adaptive one. Composed
# as a single SVG — background rect behind the foreground's own markup — so it
# goes through one rasteriser in one pass.
composed="$(mktemp --suffix=.svg)"
trap 'rm -f "$composed"' EXIT
python3 - "$fg" "$bg" "$composed" <<'PY'
import re, sys
fg, bg, out = sys.argv[1], sys.argv[2], sys.argv[3]
foreground = open(fg).read()
backdrop = re.search(r'<rect[^>]*/>', open(bg).read()).group(0)
# Straight after the opening <svg …> tag: <defs> paint nothing, so the rect
# still ends up behind every drawn element.
composed = re.sub(r'(<svg\b[^>]*>)', r'\1\n  ' + backdrop, foreground, count=1)
# The adaptive foreground keeps its art inside the 66dp safe zone of a 108dp
# canvas, because Android masks and crops it. A legacy square icon is shown
# whole, so inheriting that padding leaves the mark floating in a field of
# background. Crop the view to the middle 76dp for this path only — the
# background rect still covers it, since it is drawn at the full 108.
composed = re.sub(r'viewBox="0 0 108 108"', 'viewBox="16 16 76 76"', composed, count=1)
open(out, 'w').write(composed)
PY

for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${d%%:*}"; px="${d##*:}"
  rsvg-convert -w "$px" -h "$px" "$composed" -o "$res/mipmap-$density/ic_launcher.png"
done

echo "wrote:"
ls -1 "$res"/mipmap-*/ic_launcher*.png | sed "s|$res/||"
