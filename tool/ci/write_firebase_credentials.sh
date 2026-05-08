#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FIREBASE_PROJECT_ID:-}" ]]; then
  echo "FIREBASE_PROJECT_ID is missing." >&2
  exit 1
fi

credentials_path="${CM_BUILD_DIR:-$(pwd)}/firebase-service-account.json"

if [[ -n "${FIREBASE_SERVICE_ACCOUNT_JSON_BASE64:-}" ]]; then
  echo "$FIREBASE_SERVICE_ACCOUNT_JSON_BASE64" | base64 --decode > "$credentials_path"
elif [[ -n "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]]; then
  printf "%s" "$FIREBASE_SERVICE_ACCOUNT_JSON" > "$credentials_path"
else
  echo "FIREBASE_SERVICE_ACCOUNT_JSON_BASE64 or FIREBASE_SERVICE_ACCOUNT_JSON is missing." >&2
  exit 1
fi

gcloud auth activate-service-account --key-file="$credentials_path"
gcloud config set project "$FIREBASE_PROJECT_ID"
gcloud firebase test android models list >/dev/null

