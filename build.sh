#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat version.txt)
FORCE=0
for argument in "$@"; do
    [[ "$argument" == "--force" ]] && FORCE=1
done
if [[ "${1:-}" == "--install" && "$FORCE" != 1 ]] && pgrep -f "claude -p|codex exec" >/dev/null; then
    echo "A CAD Studio generation is running. Wait for it to finish or pass --force." >&2
    exit 1
fi
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
    osascript -e 'quit app "CAD Studio"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "CAD Studio" >/dev/null || break; sleep 0.5; done
    pkill -x "CAD Studio" || true
    rm -rf "/Applications/CAD Studio.app"
    cp -R "$APP" /Applications/
    open "/Applications/CAD Studio.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
    mkdir build/dmg && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
    hdiutil create -volname "CAD Studio" -srcfolder build/dmg -format UDZO -ov build/CADStudio.dmg
fi
