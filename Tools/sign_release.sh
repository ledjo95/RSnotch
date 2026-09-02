#!/bin/bash
# Signe un DMG de distribution pour Sparkle et affiche le bloc <item> a coller
# dans appcast.xml (voir docs/Distribution.md pour la procedure complete).
#
# La cle privee EdDSA vit dans le Trousseau de CETTE machine (generee une
# fois par `generate_keys`) — aucune mise a jour ne peut etre signee sans
# elle. Ce script ne fait que l'appeler et mettre en forme sa sortie.
#
# Usage : Tools/sign_release.sh <chemin/vers/RSnotch.dmg> <version> <build>

set -euo pipefail
cd "$(dirname "$0")/.."

DMG="${1:?usage: sign_release.sh <dmg> <version> <build>}"
VERSION="${2:?usage: sign_release.sh <dmg> <version> <build>}"
BUILD="${3:?usage: sign_release.sh <dmg> <version> <build>}"

SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*artifacts/sparkle/Sparkle/bin" -maxdepth 6 2>/dev/null | head -1)
if [ -z "$SPARKLE_BIN" ]; then
    echo "Outils Sparkle introuvables — lancer un build (xcodebuild -resolvePackageDependencies) d'abord." >&2
    exit 1
fi

SIG_LINE=$("$SPARKLE_BIN/sign_update" "$DMG")
SIGNATURE=$(echo "$SIG_LINE" | grep -oE 'sparkle:edSignature="[^"]+"' | cut -d'"' -f2)
LENGTH=$(echo "$SIG_LINE" | grep -oE 'length="[^"]+"' | cut -d'"' -f2)

if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Échec de la signature — sortie inattendue de sign_update :" >&2
    echo "$SIG_LINE" >&2
    exit 1
fi

PUB_DATE=$(LC_TIME=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat <<XML

Bloc a coller dans appcast.xml, juste apres <language>, avant le premier <item> existant :

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <!-- Résumer les changements ici -->
      ]]></description>
      <enclosure
        url="https://github.com/ledjo95/RSnotch/releases/download/v${VERSION}/RSnotch.dmg"
        sparkle:version="${BUILD}"
        sparkle:shortVersionString="${VERSION}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}"
      />
    </item>
XML
