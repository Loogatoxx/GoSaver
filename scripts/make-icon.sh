#!/bin/zsh
# Fabrique Assets/AppIcon.icns à partir du dessin IconArt (rendu par l'appli elle-même).
# À relancer seulement si le dessin de l'icône change.
set -euo pipefail
ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT"
swift build --product GoSaver
"$(swift build --show-bin-path)/GoSaver" --snapshot "$WORK" --icone

# Jeu de tailles attendu par macOS (1x et 2x).
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icone-1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/icone-1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Assets/AppIcon.icns"
cp "$WORK/icone-1024.png" "$ROOT/Assets/icone-1024.png"
echo "→ Assets/AppIcon.icns"
