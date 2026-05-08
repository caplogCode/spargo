#!/usr/bin/env bash
set -euo pipefail

derived_data_path="$PWD/build/ios_firebase_test_lab"
products_path="$derived_data_path/Build/Products"
archive_path="$PWD/build/ios_firebase_test_lab/ios_tests.zip"

rm -rf "$derived_data_path" "$archive_path"

flutter build ios \
  --debug \
  --config-only \
  --target=integration_test/app_smoke_test.dart

xcode-project use-profiles

xcodebuild build-for-testing \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphoneos \
  -derivedDataPath "$derived_data_path" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Manual

(
  cd "$products_path"
  zip -r "$archive_path" Debug-iphoneos Runner_iphoneos*.xctestrun
)

echo "iOS Firebase Test Lab archive: $archive_path"

