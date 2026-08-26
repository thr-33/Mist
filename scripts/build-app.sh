#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Mist"
DIST_DIR="$ROOT/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
BIN_DEST="$MACOS_DIR/$APP_NAME"

echo "==> Building release binary..."
swift build -c release

BIN_SRC="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_SRC" ]]; then
  echo "error: binary not found at $BIN_SRC" >&2
  exit 1
fi

echo "==> Assembling app bundle at ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

cp "$BIN_SRC" "$BIN_DEST"
chmod +x "$BIN_DEST"

if [[ -f "$ROOT/Info.plist" ]]; then
  cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
else
  cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Mist</string>
	<key>CFBundleIdentifier</key>
	<string>com.mist.app</string>
	<key>CFBundleName</key>
	<string>Mist</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST
fi

# App icon
ICNS_SRC="$ROOT/scripts/AppIcon.icns"
if [[ ! -f "$ICNS_SRC" ]]; then
  echo "==> Generating AppIcon.icns..."
  swift "$ROOT/scripts/generate-icon.swift"
fi
if [[ -f "$ICNS_SRC" ]]; then
  echo "==> Installing AppIcon.icns into bundle Resources..."
  RESOURCES_DIR="$CONTENTS/Resources"
  mkdir -p "$RESOURCES_DIR"
  cp "$ICNS_SRC" "$RESOURCES_DIR/AppIcon.icns"
else
  echo "warning: AppIcon.icns not found; bundle will have no custom icon" >&2
fi

echo "==> Ad-hoc codesign..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Bundle size:"
du -sh "$APP_BUNDLE"

SIZE_KB="$(du -sk "$APP_BUNDLE" | awk '{print $1}')"
if [[ "$SIZE_KB" -gt 1024 ]]; then
  echo "error: bundle is ${SIZE_KB} KB; keep dist/Mist.app at or below 1 MB" >&2
  exit 1
fi

echo "==> Done: $APP_BUNDLE"
