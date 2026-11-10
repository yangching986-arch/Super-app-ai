#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${API_URL:-}" ]]; then
  echo "Set API_URL, e.g. export API_URL=https://YOUR-BACKEND-DOMAIN"
  exit 1
fi
flutter pub get
if [[ ! -d android ]]; then
  flutter create --platforms=android .
fi
flutter build apk --release --dart-define="API_URL=${API_URL}"
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
