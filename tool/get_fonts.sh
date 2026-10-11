#!/usr/bin/env bash
# Downloads the open-source fonts bundled with the app (SIL Open Font License):
#  - IBM Plex Sans Arabic: app interface (Arabic + Latin)
#  - Amiri: A4 immunization card
# plus each family's OFL.txt, shown on the in-app licences page.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/fonts assets/licenses
base=https://github.com/google/fonts/raw/main/ofl
get() { curl -fsSL --retry 3 -o "$2" "$1"; }
for f in Amiri-Regular Amiri-Bold; do
  get "$base/amiri/$f.ttf" "assets/fonts/$f.ttf"
done
for w in Regular Medium SemiBold Bold; do
  get "$base/ibmplexsansarabic/IBMPlexSansArabic-$w.ttf" "assets/fonts/IBMPlexSansArabic-$w.ttf"
done
get "$base/amiri/OFL.txt" assets/licenses/Amiri-OFL.txt
get "$base/ibmplexsansarabic/OFL.txt" assets/licenses/IBMPlexSansArabic-OFL.txt
ls -l assets/fonts assets/licenses
