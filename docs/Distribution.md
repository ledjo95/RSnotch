# RSnotch — distribution

État au 2 septembre 2026. Version `2.0.1` (build `3`), cible macOS 26.0.
**Distribution : Developer ID + notarisation + Sparkle. Pas le Mac App Store.**

---

## 1. Pourquoi hors App Store

Une seule fonction impose ce choix : **masquer les jauges de volume et de
luminosité de macOS** pour ne laisser que celle de l'encoche.

Le HUD natif est dessiné par `OSDUIHelper`. Il n'est pas désactivable :

```
com.apple.OSDUIHelper.plist   →  restricted   (protégé par SIP)
SIP                            →  enabled
```

La seule prise consiste à intercepter la touche avant que le système ne la
voie, avec un `CGEventTap`, et à ne pas la relayer. Or **un processus du bac à
sable ne peut pas créer d'event tap** — et le bac à sable est obligatoire sur
le Mac App Store. Il n'y a pas de demi-mesure : c'est l'un ou l'autre.

Conséquences assumées :

| | Avant (App Store) | Maintenant (Developer ID) |
|---|---|---|
| Bac à sable | Obligatoire | Retiré |
| Signature | Apple Distribution | Developer ID Application |
| Diffusion | App Store Connect | Notarisation + distribution directe |
| API privées | Interdites | Tolérées, sous conditions (§3) |
| Jauges macOS | Cohabitent | Masquées |

## 2. Ce que le bac à sable protégeait, et ce qui le remplace

Retirer le bac à sable n'est pas anodin. Ce qui tient lieu de garde-fou :

- **Hardened Runtime** actif, exigé par la notarisation ;
- **l'interception clavier est soumise à l'autorisation Accessibilité**,
  accordée explicitement par l'utilisateur et révocable à tout moment dans
  Réglages Système ;
- **aucune donnée ne quitte la machine** — inchangé depuis le départ.

Les entitlements qui n'existaient que pour le bac à sable ont disparu :
`files.user-selected.read-only`, `files.bookmarks.app-scope`,
`scripting-targets`, `network.client`, `device.bluetooth`. Ce n'est pas un
élargissement de privilèges demandé, c'est la disparition du mécanisme qui les
exigeait. Seul reste `com.apple.security.automation.apple-events`, toujours
requis sous Hardened Runtime pour piloter Musique et Spotify.

## 3. API privée : DisplayServices

Aucune API publique ne lit ni n'écrit la luminosité de l'écran interne sur
Apple Silicon — `IODisplayGetFloatParameter` est publique mais ne trouve
**aucun** service `IODisplayConnect` sur ces machines (vérifié : zéro).

RSnotch utilise `DisplayServicesGetBrightness` / `SetBrightness`, avec trois
précautions, toutes dans `Core/Services/BrightnessControl.swift` :

1. **Résolution à l'exécution** (`dlopen` / `dlsym`), jamais un lien à
   l'édition de liens. Symbole absent → l'app démarre quand même.
2. **`isAvailable` expose l'échec**, et l'appelant ne doit alors pas avaler la
   touche : mieux vaut le HUD de macOS que des touches mortes.
3. **Tout le code privé tient dans ce fichier.** Le reste de l'app ne connaît
   que `brightness` et `setBrightness(_:)`.

Ce compromis n'aurait pas été acceptable en visant l'App Store. Le risque
restant est qu'Apple retire ces symboles à une mise à jour — d'où le repli.

## 4. La règle qui gouverne l'interception

**On n'avale une touche que si on sait appliquer soi-même le changement.**

- Volume : CoreAudio, public, lecture et écriture.
- Luminosité : `DisplayServices`, privé, isolé.

Dès que l'écriture échoue — sortie audio sans réglage logiciel, symboles
absents, autorisation révoquée — l'événement repart vers macOS, qui fera son
travail et affichera son HUD. Une touche morte serait bien pire qu'un HUD en
double.

## 5. Ce qui reste à faire

- **WeatherKit** : le widget météo est masqué du menu d'ajout tant que la
  capability n'est pas activée sur le compte développeur (voir
  `WidgetKind.unavailable`).

## 6. Mises à jour (Sparkle)

RSnotch se met à jour lui-même : `Core/Services/AutoUpdater.swift` enveloppe
`SPUStandardUpdaterController`. Seule dépendance tierce du projet — justifiée
dans `project.yml`, à côté de la déclaration du package.

**Ce que Sparkle vérifie, et ce qu'il ne vérifie pas.** La notarisation Apple
protège l'app qu'on ouvre manuellement ; elle ne dit rien du fichier qu'on
vient de télécharger avant de l'ouvrir. Chaque mise à jour listée dans
`appcast.xml` porte une signature EdDSA que l'app vérifie **avant**
d'installer quoi que ce soit — un appcast modifié sans la clé privée
correspondante est un appcast rejeté.

**La clé privée** vit dans le Trousseau de la machine qui publie (générée une
fois par `generate_keys`, jamais recommitée). Elle seule peut signer une
mise à jour que les installations existantes accepteront. La perdre revient
à devoir republier une nouvelle clé publique (`SUPublicEDKey` dans
`Info.plist`) — les mises à jour depuis les anciennes versions casseraient la
vérification.

**L'appcast** vit à la racine du dépôt (`appcast.xml`), lu depuis
`raw.githubusercontent.com/ledjo95/RSnotch/main/appcast.xml` — une URL stable,
indépendante des tags de release. `SUFeedURL` dans `Info.plist` pointe dessus.

**Aucune installation automatique.** `checkForUpdates()` est déclenché depuis
le menu (« Rechercher les mises à jour… ») et, en tâche de fond, une fois par
jour (`SUScheduledCheckInterval`). Dans les deux cas, c'est Sparkle qui
affiche sa propre fenêtre de confirmation — rien ne se télécharge ni ne
s'installe sans que l'utilisateur ait cliqué « Installer et relancer ».

## 7. Captures

`Tools/appstore_screenshots.sh <nom>` reste utilisable pour un site ou une page
de téléchargement. **Il capture l'écran tel quel** : fermer courriels, code
client et notifications avant de le lancer.

## 8. Procédure de release complète

```bash
# 1. Bump de version dans project.yml (MARKETING_VERSION, CURRENT_PROJECT_VERSION)
xcodegen generate

# 2. Archive Release
rm -rf build/RSnotch.xcarchive build/export build/dmg build/RSnotch.dmg
xcodebuild -project RSnotch.xcodeproj -scheme RSnotch \
           -configuration Release -archivePath build/RSnotch.xcarchive archive

# 3. Audit avant export — doit rester vert
Tools/preflight.sh build/RSnotch.xcarchive/Products/Applications/RSnotch.app

# 4. Export du .app signé Developer ID
xcodebuild -exportArchive -archivePath build/RSnotch.xcarchive \
           -exportOptionsPlist Tools/ExportOptions.plist -exportPath build/export

# 5. DMG — commande de base, sans habillage (voir historique du projet pour
#    la variante create-dmg si un fond personnalisé est un jour souhaité)
mkdir -p build/dmg
cp -R build/export/RSnotch.app build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "RSnotch" -srcfolder build/dmg -ov -format UDZO build/RSnotch.dmg

# 6. Notarisation (identifiants stockés une fois via `xcrun notarytool store-credentials`)
xcrun notarytool submit build/RSnotch.dmg --keychain-profile "RSnotch-notary" --wait
xcrun stapler staple build/RSnotch.dmg

# 7. Signature Sparkle — affiche le bloc <item> a ajouter dans appcast.xml.
#    Demande le mot de passe du Trousseau (cle privee EdDSA) : normal, a saisir soi-meme.
Tools/sign_release.sh build/RSnotch.dmg <version> <build>
# → coller le bloc affiché dans appcast.xml, juste après <language>,
#   avant le premier <item> existant. Écrire les notes de version dans le
#   <description> (remplace le commentaire).

# 8. Commit + push (le nouvel appcast.xml doit être sur main AVANT la release,
#    sinon l'enclosure pointe vers un asset qui n'existe pas encore)
git add -A && git commit -m "Version <version>" && git push origin main

# 9. Release GitHub — le nom du tag doit correspondre à celui utilisé
#    dans l'URL de l'enclosure (`releases/download/v<version>/RSnotch.dmg`)
gh release create v<version> build/RSnotch.dmg --repo ledjo95/RSnotch \
   --title "RSnotch <version>" --notes "…"
```
