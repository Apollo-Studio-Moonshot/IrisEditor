#!/bin/zsh
# Build IrisEditor.app bundle from the SwiftPM release binary.
# The shared Info.plist and icon sources live in Support/ and dist/ so the SwiftPM
# bundle and the Xcode app target stay in sync.
#
# The bundle is written outside the project (override with IRIS_DIST_DIR). A .app
# inside the package root is picked up by SwiftPM as a resource, which rewrites
# Package.resources and breaks the manifest; it also keeps Xcode from treating a
# stale build output as one of its own inputs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/release/IrisEditor"
DIST="${IRIS_DIST_DIR:-$HOME/Library/Developer/Xcode/DerivedData/IrisEditor-dist}"
APP="$DIST/IrisEditor.app"
ICONS="$ROOT/dist/AppIcon.icns"
SOURCE_INFO="$ROOT/Support/Info.plist"
BUNDLE_ID="com.apollostudiomoonshot.IrisEditor"
VERSION="1.5"
BUILD_NUMBER="1"

[[ -x "$BIN" ]] || { echo "error: release binary missing — run: swift build -c release" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

cp "$BIN" "$APP/Contents/MacOS/IrisEditor"
[[ -f "$ICONS" ]] && cp "$ICONS" "$APP/Contents/Resources/AppIcon.icns"

cp "$SOURCE_INFO" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "IrisEditor" "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "26.0" "$APP/Contents/Info.plist"

# Ad-hoc sign so launchd/Gatekeeper accept the locally-built bundle
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
codesign --force --sign - "$APP"

echo "built: $APP"
codesign -dv "$APP" 2>&1 | head -3
