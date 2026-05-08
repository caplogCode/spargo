#!/usr/bin/env bash
set -euo pipefail

echo "Building Android release APK for testers..."
flutter build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK_PATH" ]]; then
  echo "Android tester APK was not created at $APK_PATH" >&2
  exit 1
fi

echo "Android tester APK ready: $APK_PATH"
