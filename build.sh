#!/bin/bash
set -e

PRODUCT_NAME="DevCleaner"
APP_NAME="DevCleaner 纪"
BUNDLE_ID="com.devcleaner.app"
APP_VERSION="1.0.1"
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_BUNDLE="${APP_NAME}.app"
LEGACY_APP_BUNDLE="${PRODUCT_NAME}.app"
ICON_FILE="DevCleaner.icns"
ICON_PATH="Resources/${ICON_FILE}"
INSTALL_DIR="/Applications"

echo "🔨 Building ${APP_NAME}..."
swift build --product "${PRODUCT_NAME}"

echo "🎨 Generating app icon..."
swift Scripts/generate_app_icon.swift "${ICON_PATH}"

echo "📦 Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${PRODUCT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "${ICON_PATH}" "${APP_BUNDLE}/Contents/Resources/${ICON_FILE}"

cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_FILE}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "📲 Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_BUNDLE}"
rm -rf "${INSTALL_DIR}/${LEGACY_APP_BUNDLE}"
ditto "${APP_BUNDLE}" "${INSTALL_DIR}/${APP_BUNDLE}"

echo "✅ Build complete: ${APP_BUNDLE}"
echo "✅ Installed: ${INSTALL_DIR}/${APP_BUNDLE}"
echo "🚀 Launching..."
open "${INSTALL_DIR}/${APP_BUNDLE}"
