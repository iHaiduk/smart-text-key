#!/bin/bash
set -e

echo "🔮 Smart Text Key - DMG Packager Script"

VERSION_FILE="VERSION"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# 1. Clean previous build artifacts
echo "🧹 Cleaning previous builds..."
rm -rf dist build
mkdir -p dist
mkdir -p build/iconset

# 2. Build the binary using Swift Package Manager in release mode
echo "📦 Compiling Swift package executable in Release mode..."
swift build -c release

# 3. Create the standard macOS .app bundle structure
echo "📂 Creating .app bundle structure..."
mkdir -p "dist/SmartTextKey.app/Contents/MacOS"
mkdir -p "dist/SmartTextKey.app/Contents/Resources"

# 4. Copy the compiled binary
cp ".build/release/SmartTextKey" "dist/SmartTextKey.app/Contents/MacOS/SmartTextKey"

# 5. Create Info.plist with native accessory properties (LSUIElement hides Dock icon)
echo "📝 Creating Info.plist..."
cat <<EOF > "dist/SmartTextKey.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SmartTextKey</string>
    <key>CFBundleIdentifier</key>
    <string>com.smarttextkey.app</string>
    <key>CFBundleName</key>
    <string>SmartTextKey</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 6. Generate the high-quality .icns app icon from AppIcon.png
echo "🎨 Generating Apple .icns file using sips and iconutil..."
ICON_SRC="Resources/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
    mkdir -p build/icon.iconset
    sips -s format png -z 16 16     "$ICON_SRC" --out build/icon.iconset/icon_16x16.png
    sips -s format png -z 32 32     "$ICON_SRC" --out build/icon.iconset/icon_16x16@2x.png
    sips -s format png -z 32 32     "$ICON_SRC" --out build/icon.iconset/icon_32x32.png
    sips -s format png -z 64 64     "$ICON_SRC" --out build/icon.iconset/icon_32x32@2x.png
    sips -s format png -z 128 128   "$ICON_SRC" --out build/icon.iconset/icon_128x128.png
    sips -s format png -z 256 256   "$ICON_SRC" --out build/icon.iconset/icon_128x128@2x.png
    sips -s format png -z 256 256   "$ICON_SRC" --out build/icon.iconset/icon_256x256.png
    sips -s format png -z 512 512   "$ICON_SRC" --out build/icon.iconset/icon_256x256@2x.png
    sips -s format png -z 512 512   "$ICON_SRC" --out build/icon.iconset/icon_512x512.png
    sips -s format png -z 1024 1024 "$ICON_SRC" --out build/icon.iconset/icon_512x512@2x.png

    iconutil -c icns build/icon.iconset -o "dist/SmartTextKey.app/Contents/Resources/AppIcon.icns"
    echo "✔ Successfully compiled AppIcon.icns!"
else
    echo "⚠️ Warning: Resources/AppIcon.png not found. App icon will be empty."
fi

# 7. Optionally sign the app bundle when a Developer ID identity is available.
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    echo "🔐 Signing app bundle..."
    codesign --force --deep --options runtime --sign "$CODE_SIGN_IDENTITY" "dist/SmartTextKey.app"
else
    echo "ℹ️ CODE_SIGN_IDENTITY not set. Skipping app signing."
fi

# 8. Add drag-and-drop installation symlink to /Applications
echo "🔗 Creating drag-and-drop Applications symlink..."
ln -s /Applications "dist/Applications"

# 9. Create compressed UDZO DMG installer using native hdiutil
echo "💿 Packaging compressed DMG installer..."
hdiutil create -volname "SmartTextKey Installer" -srcfolder "dist" -ov -format UDZO "SmartTextKey.dmg"

# 10. Optionally sign and notarize the DMG.
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    echo "🔐 Signing DMG..."
    codesign --force --sign "$CODE_SIGN_IDENTITY" "SmartTextKey.dmg"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "🧾 Submitting DMG for notarization..."
    xcrun notarytool submit "SmartTextKey.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "SmartTextKey.dmg"
else
    echo "ℹ️ NOTARY_PROFILE not set. Skipping notarization."
fi

echo "✨ Success! DMG created at SmartTextKey.dmg"
