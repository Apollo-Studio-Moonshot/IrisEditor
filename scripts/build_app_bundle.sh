#!/bin/zsh
# Build IrisEditor.app bundle from the SwiftPM release binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/release/IrisEditor"
APP="$ROOT/dist/IrisEditor.app"
ICONS="$ROOT/dist/AppIcon.icns"

[[ -x "$BIN" ]] || { echo "error: release binary missing — run: swift build -c release" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/IrisEditor"
[[ -f "$ICONS" ]] && cp "$ICONS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Iris Editor</string>
    <key>CFBundleDisplayName</key>       <string>Iris Editor</string>
    <key>CFBundleExecutable</key>        <string>IrisEditor</string>
    <key>CFBundleIdentifier</key>        <string>com.apollostudiomoonshot.IrisEditor</string>
    <key>CFBundleVersion</key>           <string>1.5</string>
    <key>CFBundleShortVersionString</key><string>1.5</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSSupportsSuddenTermination</key><true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>              <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>              <string>Editor</string>
            <key>LSHandlerRank</key>                 <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array><string>net.daringfireball.markdown</string></array>
            <key>CFBundleTypeExtensions</key>
            <array><string>md</string><string>markdown</string><string>txt</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc sign so launchd/Gatekeeper accept the locally-built bundle
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
codesign --force --sign - "$APP"

echo "built: $APP"
codesign -dv "$APP" 2>&1 | head -3
