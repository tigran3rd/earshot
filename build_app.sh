#!/bin/bash
# Builds Earshot.app from the Swift package.
#
#   ./build_app.sh             release build into .build/Earshot.app
#   ./build_app.sh --install   ...and replace /Applications/Earshot.app (quits a running copy)
#
# Set SIGN_IDENTITY to choose a code-signing identity; by default the first
# "Apple Development" certificate in your keychain is used, else ad-hoc signing.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Earshot"
BUNDLE_ID="com.tigrank.earshot"
VERSION="1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP_DIR=".build/${APP_NAME}.app"

INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "Building..."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Earshot"

echo "Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/Earshot"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns" # regenerate: swift tools/make_icon.swift

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Earshot</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Earshot records the audio that apps on your Mac are playing.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so the System Audio Recording permission survives rebuilds
# (an ad-hoc signature changes every build, which makes macOS forget the grant).
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP_DIR"
else
  echo "Note: no signing identity found; signing ad hoc (the permission will reset on each build)."
  codesign --force --sign - "$APP_DIR"
fi
echo "Built ${APP_DIR}"

if $INSTALL; then
  pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP_DIR" /Applications/
  echo "Installed /Applications/${APP_NAME}.app"
fi
