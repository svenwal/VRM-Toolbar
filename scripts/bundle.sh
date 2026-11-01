#!/bin/zsh
# Builds the app plus its Notification Center widget extension and wraps them in build/VRMToolbar.app.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/VRMToolbar.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/VRMToolbar" "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources"; cp Resources/AppIcon.icns "$APP/Contents/Resources/"
BIN="$(swift build -c release --show-bin-path)"
VERSION=0.2.0
APPEX="$APP/Contents/PlugIns/VRMWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BIN/VRMWidget" "$APPEX/Contents/MacOS/"
cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VRMWidget</string>
<key>CFBundleIdentifier</key><string>world.walther.vrm-toolbar.widget</string>
<key>CFBundleName</key><string>VRM Toolbar Widgets</string>
<key>CFBundleDisplayName</key><string>VRM Toolbar</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VRMToolbar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>world.walther.vrm-toolbar</string>
<key>CFBundleName</key><string>VRM Toolbar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A stable signing identity keeps the Keychain from asking for your password after every rebuild.
# Override with SIGN_IDENTITY=...; falls back to ad-hoc (which changes identity on each build).
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier world.walther.vrm-toolbar.widget --entitlements Resources/Widget.entitlements "$APPEX"
  codesign --force --sign "$IDENTITY" --identifier world.walther.vrm-toolbar --entitlements Resources/App.entitlements "$APP"
else
  echo "warning: no signing identity found, using ad-hoc signature (Keychain will prompt after each rebuild)"
  codesign --force --sign - --entitlements Resources/Widget.entitlements "$APPEX"
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
