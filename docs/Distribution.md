# RSnotch — distribution

État au 25 août 2026. Version `1.0.0` (build `1`), cible macOS 26.0.
**Distribution : Developer ID + notarisation. Pas le Mac App Store.**

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

- **Notarisation** : jamais exécutée. Voir les commandes en §7.
- **WeatherKit** : le widget météo affiche des relevés d'exemple. La capability
  reste à activer sur le compte développeur.
- **Élément d'ouverture** : `SMAppService.mainApp` renvoie `notFound` tant que
  l'app tourne depuis DerivedData. À vérifier une fois installée dans
  `/Applications`.

## 6. Captures

`Tools/appstore_screenshots.sh <nom>` reste utilisable pour un site ou une page
de téléchargement. **Il capture l'écran tel quel** : fermer courriels, code
client et notifications avant de le lancer.

## 7. Commandes

```bash
xcodegen generate
Tools/preflight.sh

xcodebuild -project RSnotch.xcodeproj -scheme RSnotch \
           -configuration Release -archivePath build/RSnotch.xcarchive archive

xcodebuild -exportArchive -archivePath build/RSnotch.xcarchive \
           -exportOptionsPlist Tools/ExportOptions.plist -exportPath build/export

# Notarisation (compte Apple Developer requis)
xcrun notarytool submit build/export/RSnotch.zip \
      --apple-id <APPLE_ID> --team-id AKAGL7C22D --password <APP_PASSWORD> --wait
xcrun stapler staple build/export/RSnotch.app
```
