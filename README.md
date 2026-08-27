# RSnotch

Transforme l'encoche du MacBook en hub interactif : widgets, lanceur d'apps et de dossiers, gestionnaire de presse-papiers, zone de dépôt AirDrop/Pocket, contrôle Apple Music/Spotify, jauges de volume et de luminosité — habillé de Liquid Glass natif macOS 26.

## Fonctionnalités

- **Widgets** — date, musique en cours (Apple Music / Spotify), minuteur, image personnalisée, citation. Grille réorganisable en glisser-déposer.
- **Apps & dossiers** — épingle des applications et des dossiers, regroupe-les, lance-les d'un clic. Noms affichables en permanence sur demande (Réglages).
- **Presse-papiers** — historique filtré par type (texte, image, couleur, fichier), favoris, recherche.
- **Pocket / AirDrop** — dépose un fichier dans l'encoche, envoie-le en AirDrop ou garde-le le temps de le glisser ailleurs.
- **Jauges système dans l'encoche** — volume et luminosité, avec l'option de **remplacer** le HUD natif de macOS plutôt que de s'y ajouter (voir *Permissions* ci-dessous).
- **Notifications compactes** — batterie, Bluetooth, morceau en cours.
- **Teinte par bureau (Space)** — le verre du panneau peut changer de teinte selon le bureau actif.

## Installation

1. Télécharge le dernier `RSnotch.dmg` depuis l'onglet [Releases](../../releases).
2. Ouvre le DMG, glisse `RSnotch.app` dans `Applications`.
3. Lance l'app. Elle vit dans l'encoche et la barre de menus — pas de fenêtre ni d'icône dans le Dock.

L'app est **signée Developer ID et notariée par Apple** : aucun avertissement Gatekeeper ne devrait apparaître à l'ouverture.

### Configuration requise

- macOS 26 (Tahoe) ou ultérieur.
- Un Mac avec encoche pour l'expérience complète ; une barre simulée en haut de l'écran reste disponible sur les autres modèles (réglable).

## Permissions demandées

RSnotch ne fait remonter **aucune donnée hors de l'appareil**. Les autorisations système demandées servent chacune une fonction précise et sont révocables à tout moment dans Réglages Système :

| Permission | Pourquoi |
|---|---|
| **Accessibilité** | Uniquement si tu actives « Remplacer les jauges de macOS » — nécessaire pour intercepter les touches volume/luminosité avant le système et masquer le HUD natif. |
| **Automatisation (Apple Events)** | Pour lire le morceau en cours et le contrôler dans Musique ou Spotify. |
| **Bluetooth** | Pour signaler la connexion/déconnexion de tes accessoires appairés — l'app ne s'y connecte jamais. |

## Pourquoi hors Mac App Store

Masquer les jauges système de macOS exige d'intercepter les touches volume/luminosité *avant* le système (`CGEventTap`), ce qu'un processus en bac à sable ne peut pas faire. RSnotch est donc distribué en **Developer ID + notarisation**, sans bac à sable, avec le Hardened Runtime actif. Le détail complet du compromis (ce qui a changé, ce qui reste protégé) est documenté dans [`docs/Distribution.md`](docs/Distribution.md).

## Compiler depuis les sources

```bash
git clone https://github.com/ledjo95/RSnotch.git
cd RSnotch
xcodegen generate
open RSnotch.xcodeproj
```

Ou en ligne de commande :

```bash
xcodebuild -project RSnotch.xcodeproj -scheme RSnotch -configuration Release build
```

Un build compilé localement (signature de développement) fonctionne pour un usage personnel sans notarisation. Voir [`docs/Distribution.md`](docs/Distribution.md) pour la procédure complète de build signé + notarisé + DMG.

### Tests

```bash
xcodebuild test -project RSnotch.xcodeproj -scheme RSnotch -destination 'platform=macOS'
```

## Confidentialité

Toutes les données (presse-papiers, apps épinglées, préférences, Pocket) restent en local, dans le conteneur de l'app. Aucune télémétrie.

## Licence

Copyright © 2026 Joffrey Stastoli. Tous droits réservés — le code source est publié à titre de référence ; aucune licence d'utilisation, de modification ou de redistribution n'est accordée.
