#!/bin/bash
set -euo pipefail

echo "🔨 Building SyncTop in release mode..."
swift build -c release

APP_NAME="SyncTop.app"
BUILD_BIN="$(swift build -c release --show-bin-path)/SyncTop"
OUTPUT_DIR="dist"

echo "📦 Creating macOS application bundle at ${OUTPUT_DIR}/${APP_NAME}..."
rm -rf "${OUTPUT_DIR}/${APP_NAME}"
mkdir -p "${OUTPUT_DIR}/${APP_NAME}/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/${APP_NAME}/Contents/Resources"

cp "${BUILD_BIN}" "${OUTPUT_DIR}/${APP_NAME}/Contents/MacOS/SyncTop"

cat <<EOF > "${OUTPUT_DIR}/${APP_NAME}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SyncTop</string>
    <key>CFBundleIdentifier</key>
    <string>com.synctop.SyncTop</string>
    <key>CFBundleName</key>
    <string>SyncTop</string>
    <key>CFBundleDisplayName</key>
    <string>SyncTop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "${OUTPUT_DIR}/${APP_NAME}/Contents/MacOS/SyncTop"

echo "✅ Successfully packaged ${OUTPUT_DIR}/${APP_NAME}!"
echo "👉 You can run it via: open ${OUTPUT_DIR}/${APP_NAME}"
