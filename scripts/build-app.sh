#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
OUTPUT_APP_DIR="$PWD/dist/Agent Meter.app"
# iCloud can reattach FinderInfo immediately after xattr removal. Sign outside
# the synced workspace, then copy the completed bundle into dist.
BUILD_STAGE="$(mktemp -d "${TMPDIR:-/tmp/}agentmeter-build.XXXXXX")"
trap 'rm -rf "$BUILD_STAGE"' EXIT
APP_DIR="$BUILD_STAGE/Agent Meter.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" .build/AppIcon.iconset
cp "$BINARY_DIR/AgentMeter" "$APP_DIR/Contents/MacOS/AgentMeter"
cp "$BINARY_DIR/AgentMeterCapture" "$APP_DIR/Contents/Resources/AgentMeterCapture"
ditto "$BINARY_DIR/AgentMeter_AgentMeter.bundle" "$APP_DIR/Contents/Resources/AgentMeter_AgentMeter.bundle"
swift scripts/make-icon.swift .build/AppIcon-1024.png
for ICON_SIZE in 16 32 128 256 512; do
    sips -z "$ICON_SIZE" "$ICON_SIZE" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((ICON_SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentMeter</string>
<key>CFBundleIdentifier</key><string>local.agentmeter.mac</string>
<key>CFBundleName</key><string>Agent Meter</string>
<key>CFBundleDisplayName</key><string>Agent Meter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR/Contents/Resources/AgentMeterCapture"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto --norsrc --noextattr "$APP_DIR" "$OUTPUT_APP_DIR"
# File Provider may attach FinderInfo during the copy; let that update settle.
for VERIFY_ATTEMPT in 1 2 3 4 5; do
    xattr -dr com.apple.FinderInfo "$OUTPUT_APP_DIR" 2>/dev/null || true
    if codesign --verify --deep --strict "$OUTPUT_APP_DIR" 2>"$BUILD_STAGE/verify.log"; then
        break
    fi
    if [ "$VERIFY_ATTEMPT" -eq 5 ]; then
        cat "$BUILD_STAGE/verify.log" >&2
        exit 1
    fi
    sleep 0.5
done
printf 'Built: %s\n' "$OUTPUT_APP_DIR"
