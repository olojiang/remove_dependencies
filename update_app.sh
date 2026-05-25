#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="DevCleaner"
APP_NAME="DevCleaner 纪"
BUNDLE_ID="com.devcleaner.app"
APP_VERSION="1.0.1"
ICON_FILE="DevCleaner.icns"
ICON_PATH="Resources/${ICON_FILE}"
RELEASE_DIR="release"
APP_BUNDLE="${APP_NAME}.app"
LEGACY_APP_BUNDLE="${PRODUCT_NAME}.app"
APP_PATH="${RELEASE_DIR}/${APP_BUNDLE}"
INSTALL_DIR="/Applications"
APPLE_KEYS_DIR="${APPLE_KEYS_DIR:-/Users/hunter/Workspace/apple_keys}"
NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            NOTARIZE=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

load_apple_keys() {
    local metadata="${APPLE_KEYS_DIR}/apple_key_metadata.env"
    local secrets="${APPLE_KEYS_DIR}/apple_key_secrets.env"

    if [[ -f "${metadata}" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "${metadata}"
        set +a
    fi

    if [[ -f "${secrets}" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "${secrets}"
        set +a
    fi
}

prepare_codesign_keychain() {
    local p12_path="${MODERN_P12:-${APPLE_KEYS_DIR}/developer_id_application_pine_field_modern.p12}"
    local keychain_name="${MAC_CODESIGN_KEYCHAIN_NAME:-devcleaner-codesign.keychain-db}"
    local keychain_path="${HOME}/Library/Keychains/${keychain_name}"
    local keychain_password="${MAC_CODESIGN_KEYCHAIN_PASSWORD:-${APPLE_CERTIFICATE_PASSWORD:-}}"

    if [[ -z "${APPLE_CERTIFICATE_ID:-}" || -z "${APPLE_CERTIFICATE_PASSWORD:-}" || ! -f "${p12_path}" ]]; then
        return 1
    fi

    if [[ -z "${keychain_password}" ]]; then
        echo "Missing MAC_CODESIGN_KEYCHAIN_PASSWORD or APPLE_CERTIFICATE_PASSWORD" >&2
        return 1
    fi

    if [[ ! -f "${keychain_path}" ]]; then
        security create-keychain -p "${keychain_password}" "${keychain_path}"
    fi

    security unlock-keychain -p "${keychain_password}" "${keychain_path}"
    security set-keychain-settings -lut 21600 "${keychain_path}"

    local keychains=()
    local listed
    while IFS= read -r listed; do
        [[ -n "${listed}" ]] && keychains+=("${listed}")
    done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')

    local found=false
    for listed in "${keychains[@]}"; do
        if [[ "${listed}" == "${keychain_path}" ]]; then
            found=true
            break
        fi
    done

    if [[ "${found}" != true ]]; then
        security list-keychains -d user -s "${keychain_path}" "${keychains[@]}"
    fi

    if ! security find-identity -v -p codesigning "${keychain_path}" | grep -Fq "${APPLE_CERTIFICATE_ID}" \
        && security find-identity -v -p codesigning | grep -Fq "${APPLE_CERTIFICATE_ID}"; then
        echo "Developer ID identity already exists in the user keychains; reusing it."
        export CODESIGN_IDENTITY="${APPLE_CERTIFICATE_ID}"
        return 0
    fi

    if ! security find-identity -v -p codesigning "${keychain_path}" | grep -Fq "${APPLE_CERTIFICATE_ID}"; then
        if ! security import "${p12_path}" \
            -k "${keychain_path}" \
            -P "${APPLE_CERTIFICATE_PASSWORD}" \
            -T /usr/bin/codesign \
            -T /usr/bin/productsign; then
            if security find-identity -v -p codesigning | grep -Fq "${APPLE_CERTIFICATE_ID}"; then
                echo "Developer ID identity already exists in another keychain; reusing it."
                export CODESIGN_IDENTITY="${APPLE_CERTIFICATE_ID}"
                return 0
            fi
            return 1
        fi
    fi

    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${keychain_password}" "${keychain_path}" >/dev/null
    export MAC_CODESIGN_KEYCHAIN="${keychain_path}"
    export CODESIGN_IDENTITY="${APPLE_CERTIFICATE_ID}"
}

create_info_plist() {
    cat > "${APP_PATH}/Contents/Info.plist" << PLIST
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
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>DevCleaner needs access to scan and remove selected dependency folders under Desktop projects.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>DevCleaner needs access to scan and remove selected dependency folders under Documents projects.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>DevCleaner needs access to scan and remove selected dependency folders under Downloads projects.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>DevCleaner needs access to scan and remove selected dependency folders on network volumes.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>DevCleaner needs access to scan and remove selected dependency folders on removable volumes.</string>
</dict>
</plist>
PLIST
}

sign_app() {
    if [[ "${NOTARIZE}" == true ]]; then
        echo "Ad-hoc signing cannot be notarized. Run without --sign." >&2
        exit 1
    fi

    echo "🔏 Signing with ad-hoc identity"
    codesign --force --deep --sign - "${APP_PATH}"
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
}

notarize_app() {
    [[ "${NOTARIZE}" == true ]] || return 0

    if [[ -z "${APPLE_API_KEY_PATH:-}" || -z "${APPLE_API_KEY:-}" || -z "${APPLE_API_ISSUER:-}" ]]; then
        echo "Missing APPLE_API_KEY_PATH, APPLE_API_KEY, or APPLE_API_ISSUER for notarization" >&2
        exit 1
    fi

    local archive="${RELEASE_DIR}/${PRODUCT_NAME}-notarize.zip"
    rm -f "${archive}"
    ditto -c -k --keepParent "${APP_PATH}" "${archive}"

    echo "📬 Submitting for notarization..."
    xcrun notarytool submit "${archive}" \
        --key "${APPLE_API_KEY_PATH}" \
        --key-id "${APPLE_API_KEY}" \
        --issuer "${APPLE_API_ISSUER}" \
        --wait

    xcrun stapler staple "${APP_PATH}"
    spctl --assess --type execute --verbose=4 "${APP_PATH}"
}

kill_running_app() {
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    pkill -x "${PRODUCT_NAME}" >/dev/null 2>&1 || true
    sleep 1
}

clean_moved_build_cache() {
    local package_root
    local stamp_file
    package_root="$(cd "$(dirname "$0")" && pwd)"
    stamp_file=".build/${PRODUCT_NAME}.source-root"

    if [[ -d ".build" && (! -f "${stamp_file}" || "$(cat "${stamp_file}")" != "${package_root}") ]]; then
        echo "🧹 Cleaning SwiftPM cache for this checkout..."
        swift package clean
    fi

    mkdir -p ".build"
    printf '%s\n' "${package_root}" > "${stamp_file}"
}

clean_moved_build_cache

echo "🔨 Building ${APP_NAME}..."
swift build -c release --product "${PRODUCT_NAME}"
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "🎨 Generating app icon..."
swift Scripts/generate_app_icon.swift "${ICON_PATH}"

echo "📦 Creating app bundle..."
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"
cp "${BIN_DIR}/${PRODUCT_NAME}" "${APP_PATH}/Contents/MacOS/"
cp "${ICON_PATH}" "${APP_PATH}/Contents/Resources/${ICON_FILE}"
create_info_plist

sign_app
notarize_app

echo "🛑 Stopping existing app process..."
kill_running_app

echo "📲 Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_BUNDLE}" "${INSTALL_DIR}/${LEGACY_APP_BUNDLE}"
ditto "${APP_PATH}" "${INSTALL_DIR}/${APP_BUNDLE}"

echo "🚀 Launching ${INSTALL_DIR}/${APP_BUNDLE}..."
open "${INSTALL_DIR}/${APP_BUNDLE}"

echo "✅ Updated: ${INSTALL_DIR}/${APP_BUNDLE}"
