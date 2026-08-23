#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Converts the live <text> in the Garfin wordmark and lockups to vector paths.
# Run this on a machine with Fredoka and Nunito installed, before shipping any asset.
#
#   sudo dnf install inkscape          # Fedora
#   sudo apt install inkscape          # Pop!_OS / Debian
#
# Install the fonts first (once):
#   mkdir -p ~/.local/share/fonts
#   # download Fredoka + Nunito from fonts.google.com, unzip the .ttf files there
#   fc-cache -fv
#   fc-list | grep -Ei 'fredoka|nunito'   # verify
set -euo pipefail

# Run from the brand/ directory:  cd brand && ./outline.sh
cd "$(dirname "$0")"

command -v inkscape >/dev/null || { echo "inkscape not found"; exit 1; }
fc-list | grep -qi fredoka || { echo "Fredoka is not installed — text would render as a fallback font"; exit 1; }

mkdir -p svg/outlined
for f in garfin-wordmark garfin-wordmark-mono garfin-lockup-h garfin-lockup-v; do
  inkscape "svg/$f.svg" \
    --actions="select-all;object-to-path;export-plain-svg;export-filename:svg/outlined/$f-outlined.svg;export-do"
  echo "→ svg/outlined/$f-outlined.svg"
done

# PNG exports for the places that will not take an SVG
mkdir -p png
inkscape svg/garfin-mark.svg -w 512 -h 512 -o png/icon-512.png
for s in 192 144 96 72 48; do
  inkscape svg/garfin-mark.svg -w $s -h $s -o "png/mark-${s}.png"
done
inkscape svg/outlined/garfin-lockup-h-outlined.svg -w 1280 -o png/readme-banner-1280.png
echo "done."
