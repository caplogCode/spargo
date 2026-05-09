#!/usr/bin/env bash
set -euo pipefail

EXPORT_METHOD="${IOS_EXPORT_METHOD:-ad-hoc}"
EXPORT_OPTIONS_PLIST="$HOME/export_options.plist"
SIGNING_TYPE="IOS_APP_ADHOC"

if [[ "$EXPORT_METHOD" = "app-store" ]]; then
  SIGNING_TYPE="IOS_APP_STORE"
fi

echo "Preparing iOS signing for tester IPA with export method: $EXPORT_METHOD"
app-store-connect fetch-signing-files "$BUNDLE_ID" --type "$SIGNING_TYPE" --create
keychain add-certificates
xcode-project use-profiles

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadBitcode</key>
  <false/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
EOF

echo "Building iOS IPA for testers..."
MAPS_DEFINE=()
if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  MAPS_DEFINE=(--dart-define "GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY}")
fi

flutter build ipa --release "${MAPS_DEFINE[@]}" --export-options-plist="$EXPORT_OPTIONS_PLIST"

IPA_COUNT="$(find build/ios/ipa -name '*.ipa' -type f | wc -l | tr -d ' ')"
if [[ "$IPA_COUNT" = "0" ]]; then
  echo "iOS tester IPA was not created under build/ios/ipa" >&2
  exit 1
fi

echo "iOS tester IPA ready under build/ios/ipa"
