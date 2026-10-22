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
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# Signature. Avec le certificat local « GoSaver Dev » (créé une fois dans le trousseau),
# l'identité de l'appli reste la même d'une compilation à l'autre : macOS garde donc
# l'accès complet au disque. Sans lui, repli sur une signature « ad hoc », qui change
# à chaque compilation (l'accès est alors perdu à chaque fois).
SIGN_ID="${GOSAVER_SIGN_ID:-GoSaver Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  codesign --force --deep --sign "$SIGN_ID" "$APP"
  echo "Signé avec « $SIGN_ID »"
else
  codesign --force --deep --sign - "$APP"
  echo "Signé ad hoc (certificat « $SIGN_ID » introuvable)"
fi
echo "→ $APP"
