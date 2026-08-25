#!/usr/bin/env python3
"""Genere l'icone de RSnotch dans Resources/Assets.xcassets/AppIcon.appiconset.

Le dessin reprend la direction visuelle du panneau : fond d'encre, encoche
posee en haut, filament ambre dessous. Aucun asset tiers, tout est trace ici —
c'est la condition posee par le brief (pas de copie d'assets, pas de marque).

Usage : python3 Tools/make_appicon.py
"""

from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "RSnotch/Resources/Assets.xcassets/AppIcon.appiconset"

INK = (10, 10, 13)
INK_TOP = (46, 48, 58)
EMBER = (255, 138, 61)
GLASS = (255, 255, 255)

# Canevas macOS : la forme occupe 824 pt sur 1024, le reste est une marge que
# le systeme attend (ombre portee, alignement avec les autres icones du Dock).
CANVAS = 1024
SHAPE = 824
MARGIN = (CANVAS - SHAPE) // 2
RADIUS = 185  # rayon macOS Big Sur+ pour une forme de 824


def rounded_mask(size, radius, scale=4):
    """Masque anticrenele : on trace en grand puis on reduit."""
    big = Image.new("L", (size * scale, size * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [0, 0, size * scale - 1, size * scale - 1],
        radius=radius * scale, fill=255,
    )
    return big.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel((0, y), tuple(
            int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return grad.resize((size, size))


def build():
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    body = vertical_gradient(SHAPE, INK_TOP, INK).convert("RGBA")
    body.putalpha(rounded_mask(SHAPE, RADIUS))
    icon.paste(body, (MARGIN, MARGIN), body)

    draw = ImageDraw.Draw(icon)

    # Tout ce qui est translucide passe par un calque compose : dessine
    # directement, `ImageDraw` ECRIT l'alpha au lieu de melanger, et laisse des
    # trous a travers lesquels le fond du Dock transparaitrait.
    overlay = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    over = ImageDraw.Draw(overlay)

    # L'encoche : une pilule NOIRE suspendue au bord haut, comme l'encoche
    # physique. Claire, elle se lisait comme une morsure dans la forme — le
    # contraire de ce que l'icone doit dire.
    notch_w, notch_h = 392, 128
    nx = (CANVAS - notch_w) // 2
    ny = MARGIN
    draw.rounded_rectangle(
        [nx, ny - notch_h, nx + notch_w, ny + notch_h],
        radius=56, fill=(4, 4, 6, 255),
    )
    # Liseré : sans lui, la pilule se perd dans le degrade a petite taille.
    over.rounded_rectangle(
        [nx, ny - notch_h, nx + notch_w, ny + notch_h],
        radius=56, outline=(255, 255, 255, 46), width=4,
    )

    # Filament : la signature du panneau. Legere lueur dessous, obtenue par un
    # flou, puis le trait net par-dessus.
    fy = ny + notch_h + 84
    fx0, fx1 = MARGIN + 96, CANVAS - MARGIN - 96

    glow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        [fx0, fy - 14, fx1, fy + 14], radius=14, fill=EMBER + (150,),
    )
    overlay.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26)))

    over.rounded_rectangle([fx0, fy - 7, fx1, fy + 7], radius=7, fill=EMBER + (255,))

    # Deux traits courts sous le filament : la rangee de cartes, suggeree.
    card_y = fy + 104
    for x0, x1 in ((MARGIN + 96, CANVAS // 2 - 26), (CANVAS // 2 + 26, CANVAS - MARGIN - 96)):
        over.rounded_rectangle(
            [x0, card_y, x1, card_y + 168], radius=40,
            fill=(255, 255, 255, 26), outline=(255, 255, 255, 54), width=4,
        )

    icon.alpha_composite(overlay)

    # Le contenu deborde volontairement de la forme (l'encoche mord le bord
    # haut) : on redecoupe pour que rien ne sorte du gabarit.
    clip = Image.new("L", (CANVAS, CANVAS), 0)
    clip.paste(rounded_mask(SHAPE, RADIUS), (MARGIN, MARGIN))
    icon.putalpha(Image.composite(icon.getchannel("A"), Image.new("L", (CANVAS, CANVAS), 0), clip))
    return icon


def main():
    master = build()
    ICONSET.mkdir(parents=True, exist_ok=True)

    entries = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size * scale
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(ICONSET / name)
            entries.append({
                "idiom": "mac", "size": f"{size}x{size}",
                "scale": f"{scale}x", "filename": name,
            })

    (ICONSET / "Contents.json").write_text(json.dumps(
        {"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2
    ) + "\n")
    print(f"icone generee : {len(entries)} tailles dans {ICONSET}")


if __name__ == "__main__":
    main()
