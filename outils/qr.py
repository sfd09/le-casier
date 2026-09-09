#!/usr/bin/env python3
# Fabrique les deux QR du Casier.
#
#   python3 outils/qr.py
#
# Le QR « lien » ne change jamais : l'adresse du site est stable.
# Le QR « installeur » porte un suffixe ?v=<date> qui force le
# navigateur à recharger l'application au lieu de servir sa copie en
# cache. Il est donc à refaire à chaque changement de version — c'est
# la seule raison d'être de ce script.

import re, pathlib, segno
from PIL import Image, ImageDraw, ImageFont

RACINE = pathlib.Path(__file__).resolve().parent.parent
SITE   = "https://sfd09.github.io/le-casier/"

ENCRE  = (21, 29, 49)      # --ink
SOURD  = (93, 104, 131)    # --muted
PAPIER = (255, 255, 255)
BARRES = [(47, 95, 224), (178, 58, 72), (27, 122, 79)]   # accent, lecture, sport

GRAS   = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def version_app():
    """La version affichée dans l'application fait foi."""
    t = (RACINE / "index.html").read_text(encoding="utf-8")
    m = re.search(r'VERSION_APP\s*=\s*"([^"]+)"', t)
    if not m:
        raise SystemExit("VERSION_APP introuvable dans index.html")
    return m.group(1)


def dessiner(sortie, donnees, titre, legende, large=620, marge=48):
    qr = segno.make(donnees, error="h")          # 30 % de tolérance : un QR
    tmp = RACINE / "outils" / "_qr.png"          # imprimé se salit, se plie
    # Un module doit tomber sur un nombre entier de pixels, sinon les
    # carrés bavent les uns sur les autres et les lecteurs peinent.
    modules = segno.make(donnees, error="h").symbol_size(scale=1, border=0)[0]
    qr.save(tmp, scale=max(1, round((large - 2 * marge) / modules)),
            border=0, dark="#151D31", light="#FFFFFF")
    grille = Image.open(tmp)

    f_titre = ImageFont.truetype(GRAS, 30)
    f_leg   = ImageFont.truetype(GRAS, 19)

    largeur = grille.width + marge * 2
    hauteur = grille.height + marge * 2 + 130
    im = Image.new("RGB", (largeur, hauteur), PAPIER)
    im.paste(grille, (marge, marge))

    d = ImageDraw.Draw(im)
    y = marge + grille.height + 40

    # Les trois barres de l'icône : trois circuits, don, troc, vente.
    lb, hb, ec = 15, 40, 9
    x = (largeur - (3 * lb + 2 * ec)) // 2
    for i, c in enumerate(BARRES):
        h = hb if i == 1 else int(hb * 0.72)
        hx = x + i * (lb + ec)
        d.rounded_rectangle([hx, y + (hb - h) // 2, hx + lb, y + (hb - h) // 2 + h],
                            radius=4, fill=c)
    y += hb + 26

    for texte, police, couleur in ((titre, f_titre, ENCRE), (legende, f_leg, SOURD)):
        l = d.textbbox((0, 0), texte, font=police)[2]
        d.text(((largeur - l) // 2, y), texte, font=police, fill=couleur)
        y += police.size + 14

    im.save(RACINE / sortie)
    tmp.unlink()
    print(f"{sortie:22} {im.width}×{im.height}  →  {donnees}")


if __name__ == "__main__":
    v = version_app()                      # ex. 2026.09.09-1
    jour = v.split("-")[0].replace(".", "")  # → 20260909

    dessiner("qr-le-casier.png", SITE,
             "Le Casier du lycée", "sfd09.github.io/le-casier", large=620)

    dessiner("qr-installer.png", f"{SITE}?v={jour}",
             f"Le Casier — version {v}", "force le chargement de la nouvelle version",
             large=750)
