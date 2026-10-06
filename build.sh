#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat version.txt)
APP="build/CAD Studio.app"
rm -rf build && mkdir -p build
xcodebuild \
    -project CADStudio.xcodeproj \
    -scheme CADStudio \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    -quiet \
    build
cp -R "build/DerivedData/Build/Products/Release/CAD Studio.app" build/
codesign --force --deep --options runtime --sign - "$APP"
echo "Built $APP $VERSION"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "CAD Studio" || true
    rm -rf "/Applications/CAD Studio.app"
    cp -R "$APP" /Applications/
    open "/Applications/CAD Studio.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
    mkdir build/dmg && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
    hdiutil create -volname "CAD Studio" -srcfolder build/dmg -format UDZO -ov build/CADStudio.dmg
fi
