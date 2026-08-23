#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Renders the in-app brand mark from brand/svg/ into assets/brand/ (#66).
#
# The PNGs under assets/ are **output, not source**. Edit the SVG and re-run
# this; never hand-edit a bitmap, or the next change to the mark starts from
# whatever the last person exported.
#
# Not the launcher icon. Those are Android resources under
# android/app/src/main/res/mipmap-*/ and are generated separately (#67) at
# Android's own densities and safe zone; this one is a Flutter asset at
# Flutter's 1x/2x/3x, for the About screen.
#
# Needs rsvg-convert (librsvg). Debian/Ubuntu: apt install librsvg2-bin.
set -euo pipefail

cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert not found (apt install librsvg2-bin)" >&2
  exit 1
}

# 84dp is the size the About screen draws it at, so 1x is 84px and the rest
# follow. Rendering exactly what is displayed rather than something larger:
# a downscale at paint time is the launcher-icon mistake in miniature — it
# looks fine on the machine that made it and soft on a phone.
readonly BASE=84
readonly SRC="brand/svg/garfin-mark.svg"
readonly OUT="assets/brand"

mkdir -p "$OUT/2.0x" "$OUT/3.0x"

render() { # scale, destination
  local px=$((BASE * $1))
  rsvg-convert --width="$px" --height="$px" --keep-aspect-ratio \
    --background-color=none "$SRC" --output="$2/garfin-mark.png"
  echo "  ${px}px -> $2/garfin-mark.png"
}

echo "rendering $SRC with $(rsvg-convert --version)"
render 1 "$OUT"
render 2 "$OUT/2.0x"
render 3 "$OUT/3.0x"

echo "done. Commit the PNGs — pub does not run this."
