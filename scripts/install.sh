#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building clavier (Release)…"
xcodebuild \
  -project clavier.xcodeproj \
  -scheme clavier \
  -configuration Release \
  -derivedDataPath build \
  -quiet \
  build

APP_BUILT="build/Build/Products/Release/clavier.app"
APP_INSTALLED="/Applications/clavier.app"

if [[ ! -d "$APP_BUILT" ]]; then
  echo "error: build did not produce $APP_BUILT" >&2
  exit 1
fi

echo "==> Stopping running instance (if any)…"
killall clavier 2>/dev/null || true

echo "==> Installing to $APP_INSTALLED…"
rm -rf "$APP_INSTALLED"
cp -R "$APP_BUILT" "$APP_INSTALLED"

echo "==> Launching…"
open "$APP_INSTALLED"

echo "==> Done."
