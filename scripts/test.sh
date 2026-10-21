#!/bin/zsh
# Lance les tests sans Xcode : le framework Swift Testing des Command Line Tools
# n'est pas dans le chemin de recherche par défaut, on le donne explicitement.
set -euo pipefail
cd "${0:A:h:h}"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test \
  -Xswiftc -F -Xswiftc "$F" \
  -Xlinker -F -Xlinker "$F" \
  -Xlinker -rpath -Xlinker "$F" \
  -Xlinker -rpath -Xlinker "$L" "$@"
