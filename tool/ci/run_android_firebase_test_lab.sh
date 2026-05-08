#!/usr/bin/env bash
set -euo pipefail

device="${FIREBASE_ANDROID_DEVICE:-model=Pixel2,version=30,locale=de,orientation=portrait}"
timeout_value="${FIREBASE_TEST_TIMEOUT:-12m}"
results_args=()

if [[ -n "${FIREBASE_TESTLAB_RESULTS_BUCKET:-}" ]]; then
  results_args+=(--results-bucket "$FIREBASE_TESTLAB_RESULTS_BUCKET")
fi

flutter build apk --debug --target=integration_test/app_smoke_test.dart
(
  cd android
  ./gradlew app:assembleAndroidTest
)

gcloud firebase test android run \
  --type instrumentation \
  --app build/app/outputs/flutter-apk/app-debug.apk \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --device "$device" \
  --timeout "$timeout_value" \
  "${results_args[@]}"

