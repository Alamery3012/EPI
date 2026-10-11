#!/usr/bin/env bash
# Downloads the Amiri Arabic font (SIL Open Font License) used by the A4 card.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/fonts
for f in Amiri-Regular Amiri-Bold; do
  curl -fsSL --retry 3 -o "assets/fonts/$f.ttf" "https://github.com/google/fonts/raw/main/ofl/amiri/$f.ttf"
done
ls -l assets/fonts
