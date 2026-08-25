#!/bin/bash
# Captures pour la fiche App Store (Phase 11).
#
# App Store Connect n'accepte, pour macOS, que quatre tailles exactes :
# 1280×800, 1440×900, 2560×1600, 2880×1800. Une capture d'ecran de MacBook
# 16 pouces ne tombe sur aucune : elle est recadree/redimensionnee ici, avec
# un fond neutre plutot qu'un etirement qui deformerait le panneau.
#
# ATTENTION : la capture prend l'ecran TEL QUEL. Ferme ce qui ne doit pas
# figurer sur une fiche publique — courriels, code client, notifications.
#
# Usage : Tools/appstore_screenshots.sh <nom> [delai]
#   nom   : suffixe du fichier (ex. « widgets », « presse-papiers »)
#   delai : secondes avant la capture, pour placer la souris (defaut 5)

set -euo pipefail

NAME="${1:?usage: appstore_screenshots.sh <nom> [delai]}"
DELAY="${2:-5}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Tools/screenshots"
mkdir -p "$OUT"
RAW="$OUT/.raw_$NAME.png"

echo "Capture dans $DELAY s — place le pointeur sur l'encoche pour ouvrir le panneau."
for i in $(seq "$DELAY" -1 1); do printf '\r  %s… ' "$i"; sleep 1; done
echo
screencapture -x "$RAW"

python3 - "$RAW" "$OUT" "$NAME" <<'PY'
import sys
from PIL import Image

raw, out, name = sys.argv[1], sys.argv[2], sys.argv[3]
src = Image.open(raw).convert("RGB")

# Fond pris sur un pixel du bureau plutot qu'un noir arbitraire : les bandes
# laterales se fondent alors dans la capture au lieu de l'encadrer.
backdrop = src.getpixel((8, src.height - 8))

for w, h in ((2880, 1800), (2560, 1600), (1440, 900), (1280, 800)):
    scale = min(w / src.width, h / src.height)
    resized = src.resize(
        (round(src.width * scale), round(src.height * scale)), Image.LANCZOS
    )
    canvas = Image.new("RGB", (w, h), backdrop)
    canvas.paste(resized, ((w - resized.width) // 2, (h - resized.height) // 2))
    path = f"{out}/{name}_{w}x{h}.png"
    canvas.save(path)
    print(f"  {path}")
PY

rm -f "$RAW"
echo "Prêt pour App Store Connect."
