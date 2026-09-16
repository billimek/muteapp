#!/usr/bin/env bash
# Builds Release, ad-hoc signs, verifies the signature, zips muteapp.app, prints SHA256.
# Usage: tools/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR

xcodebuild \
    -project muteapp.xcodeproj \
    -scheme muteapp \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY=- \
    build >/dev/null

APP="build/Build/Products/Release/muteapp.app"
[[ -d "$APP" ]] || { echo "Build did not produce $APP"; exit 1; }

# A linker-only signature over the Mach-O is not enough; macOS rejects the bundle as damaged.
[[ -d "$APP/Contents/_CodeSignature" ]] || { echo "Bundle is not signed: $APP/Contents/_CodeSignature missing"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="dist/muteapp-$VERSION.zip"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "Built $ZIP"
echo "SHA256: $SHA"
