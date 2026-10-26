#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Camera Tuner.app"
TARGET="$(uname -m)-apple-macos14.0"

SOURCES=("$ROOT"/CameraTuner/**/*.swift)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "$TARGET" \
  "${SOURCES[@]}" \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreImage \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework IOKit \
  -framework Metal \
  -framework MetalKit \
  -framework SwiftUI \
  -o "$APP/Contents/MacOS/CameraTuner"

cp "$ROOT/CameraTuner/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/CameraTuner/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
touch "$APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi

echo "Built: $APP"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
