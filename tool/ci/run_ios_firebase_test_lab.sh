#!/usr/bin/env bash
set -euo pipefail

test_archive="${CM_BUILD_DIR:-$(pwd)}/build/ios_firebase_test_lab/ios_tests.zip"
device="${FIREBASE_IOS_DEVICE:-model=iphone14,version=16.6,locale=de_DE,orientation=portrait}"
timeout_value="${FIREBASE_TEST_TIMEOUT:-12m}"
results_args=()

if [[ -n "${FIREBASE_TESTLAB_RESULTS_BUCKET:-}" ]]; then
  results_args+=(--results-bucket "$FIREBASE_TESTLAB_RESULTS_BUCKET")
fi

if [[ ! -f "$test_archive" ]]; then
  echo "Missing iOS XCTest archive: $test_archive" >&2
  exit 1
fi

gcloud firebase test ios run \
  --test "$test_archive" \
  --device "$device" \
  --timeout "$timeout_value" \
  "${results_args[@]}"

