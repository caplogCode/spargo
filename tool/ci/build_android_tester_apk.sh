#!/usr/bin/env bash
set -euo pipefail

echo "Building Android release APK for testers..."
MAPS_DEFINE=()
if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  MAPS_DEFINE=(--dart-define "GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY}")
fi

flutter build apk --release "${MAPS_DEFINE[@]}"

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK_PATH" ]]; then
  echo "Android tester APK was not created at $APK_PATH" >&2
  exit 1
fi

echo "Android tester APK ready: $APK_PATH"
