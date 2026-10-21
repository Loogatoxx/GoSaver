#!/bin/zsh
# Assemble GoSaver.app à partir de la compilation SwiftPM.
# Usage : scripts/bundle.sh [debug|release]   (release par défaut)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="${0:A:h:h}"
APP="$ROOT/build/GoSaver.app"
VERSION="0.1.0"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GoSaver" "$APP/Contents/MacOS/GoSaver"
cp -R "$ROOT/Sources/GoSaver/Resources/Fonts" "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GoSaver</string>
    <key>CFBundleDisplayName</key><string>GoSaver</string>
    <key>CFBundleIdentifier</key><string>fr.carlos.gosaver</string>
    <key>CFBundleExecutable</key><string>GoSaver</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>ATSApplicationFontsPath</key><string>Fonts</string>
</dict>
</plist>
PLIST

# Signature « ad hoc » : pas de certificat développeur, mais macOS exige
# une signature valide pour lancer l'appli sur Apple Silicon.
codesign --force --deep --sign - "$APP"
echo "→ $APP"
