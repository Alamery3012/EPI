#!/usr/bin/env bash
# One-command local build for macOS / Linux. Needs Flutter, Android SDK, Java 17, Python 3.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --org org.yfca --project-name epi_app --platforms android .
bash tool/get_fonts.sh
python3 tool/patch_android.py
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
echo
echo "APK ready: build/app/outputs/flutter-apk/app-release.apk"
