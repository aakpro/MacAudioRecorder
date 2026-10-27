#!/usr/bin/env bash
set -euo pipefail

# InternalSoundRecorder App Bundler Script
echo "==> Building InternalSoundRecorder in Release mode..."
swift build -c release

BIN_DIR=$(swift build -c release --show-bin-path)
APP_NAME="InternalSoundRecorder"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Packaging into ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
if [ -f "Resources/Info.plist" ]; then
    cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
else
    echo "Warning: Resources/Info.plist not found, generating minimal Info.plist"
    cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.internalsoundrecorder.app</string>
    <key>CFBundleName</key>
    <string>InternalSoundRecorder</string>
    <key>CFBundleExecutable</key>
    <string>InternalSoundRecorder</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
fi

# Create PkgInfo
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

# Ad-hoc code sign for macOS ScreenCaptureKit permissions
echo "==> Code signing app bundle..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "==> Validating app bundle signature..."
codesign -vvv "${BUNDLE_DIR}"

echo "==> Success! App bundle created at ${BUNDLE_DIR}"
