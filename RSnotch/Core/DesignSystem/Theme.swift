import SwiftUI

// MARK: - Design tokens
//
// Direction visuelle « lunette d'instrument » : le panneau se lit comme le
// boitier usine d'un appareil de mesure, creuse dans la dalle et ECLAIRE DE
// L'INTERIEUR. Ce n'est pas une metaphore decorative, c'est la regle qui
// tranche chaque arbitrage visuel : la lumiere vient du HAUT-INTERIEUR de la
// coquille, donc toute arete tournee vers le haut l'accroche et toute arete
// basse tombe dans l'ombre.
//
// LE VERRE SE LIT PAR SES ARETES, PAS PAR SON FLOU. C'est le point qui a
// manqué a la premiere version : la coquille etait bien du Liquid Glass, puis
// chaque carte reposait un aplat opaque par-dessus et annulait le materiau.
// Le rendu tenait du tableau de bord sombre, pas du verre. Les cartes sont
// donc devenues des CREUX (`well`) cernes d'une arete DIRECTIONNELLE (`rim`) :
// un liseré d'epaisseur uniforme signe la bordure web, un liseré qui s'eteint
// vers le bas signe le biseau.
//
// Une seule audace, declinee a deux echelles : le « filament » — la lumiere
// qui s'echappe sous la coquille, reprise en sourdine sur l'arete haute de
// chaque carte.

enum Theme {

    // MARK: Palette
    // Definie une seule fois ici. Aucun Color litteral ailleurs dans l'app.
    enum Palette {
        /// Noir du notch physique. Reference de fond quand le verre est desactive.
        static let ink = Color(red: 0.031, green: 0.031, blue: 0.039)
        /// Gris de surface franc. Ne sert plus de fond de carte — les cartes
        /// sont devenues des creux (`wellFill`) — mais reste le fond des
        /// elements qui doivent rester OPAQUES : pilules de filtre, zones de
        /// depot, cadre d'attente d'une pochette. Un creux translucide y
        /// laisserait passer le bureau et brouillerait la cible.
        static let slate = Color(red: 0.086, green: 0.090, blue: 0.102)
        /// Accent principal : ambre chaud (actions primaires, minuteur).
        static let ember = Color(red: 1.0, green: 0.541, blue: 0.239)
        /// Marqueur temporel (jour de la semaine, alertes courtes).
        static let signal = Color(red: 1.0, green: 0.271, blue: 0.227)
        /// Texte principal. Jamais du blanc pur : sur un fond de verre, le blanc
        /// pur vibre et durcit la lecture.
        static let frost = Color.white.opacity(0.94)
        /// Texte secondaire. Volontairement plus efface qu'avant (0,62 → 0,54) :
        /// deux niveaux de gris trop proches ne font pas une hierarchie.
        static let mist = Color.white.opacity(0.54)
        /// Liseré de verre : contour interne des formes. Sert de valeur haute au
        /// degrade d'arete, pas de trait uniforme (voir `rim`).
        static let filament = Color.white.opacity(0.16)

        // MARK: Verre

        /// Creux d'une carte. Un DEGRADE, pas un aplat : le haut capte la
        /// lumiere interne de la coquille, le bas s'enfonce. C'est ce qui fait
        /// lire la carte comme taillee DANS le verre plutot que posee dessus.
        static let wellFill = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.070), location: 0.0),
                .init(color: .white.opacity(0.030), location: 0.45),
                .init(color: .white.opacity(0.014), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Arete d'une carte. Vive en haut, eteinte en bas — un biseau, pas une
        /// bordure. C'est le seul detail qui distingue une carte de verre d'un
        /// rectangle gris, et il ne coute qu'un `strokeBorder`.
        static let rim = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.46), location: 0.0),
                .init(color: .white.opacity(0.13), location: 0.35),
                .init(color: .white.opacity(0.05), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Arete d'un element pose SUR une carte (tuile, pastille). Deux fois
        /// plus discrete que `rim` : empiler deux biseaux de meme force ferait
        /// vibrer la grappe d'icones.
        static let innerRim = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.20), location: 0.0),
                .init(color: .white.opacity(0.05), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Metriques
    enum Metrics {
        /// Rayon des coins bas du notch physique sur les MacBook a encoche.
        /// Sert de base a la concentricite : tout rayon superieur s'en deduit.
        static let notchCornerRadius: CGFloat = 12

        /// Rayon du panneau etendu. Concentrique = rayon interne + padding.
        static let panelCornerRadius: CGFloat = 24
        /// Rayon des cartes internes (widgets, tuiles).
        static let cardCornerRadius: CGFloat = 16
        /// Rayon des pilules (onglets de filtre, boutons ronds).
        static let pillCornerRadius: CGFloat = 999

        /// Espacement passe a GlassEffectContainer : distance en deca de laquelle
        /// deux formes de verre fusionnent pendant le morph.
        static let glassFusionSpacing: CGFloat = 22

        /// Signature : epaisseur du filament lumineux sous le panneau.
        static let filamentWidth: CGFloat = 1

        /// Marge verticale interne du panneau. Sert aussi de base au calcul de
        /// concentricite des coins.
        static let panelPadding: CGFloat = 10
        /// Marge horizontale interne, volontairement plus large que la marge
        /// verticale : le panneau reste compact, mais le contenu ne vient pas
        /// buter contre les flancs arrondis de la coquille.
        static let panelHorizontalPadding: CGFloat = 24
        static let contentSpacing: CGFloat = 8

        /// Hauteur utile du panneau etendu (sous la barre d'onglets).
        static let expandedContentHeight: CGFloat = 188

        /// Chaque onglet impose sa propre hauteur utile : le presse-papiers
        /// porte une rangee de filtres au-dessus de ses cartes, la rangee de
        /// widgets non. Un gabarit unique obligerait a caler tous les onglets
        /// sur le plus haut, et le panneau paraitrait vide partout ailleurs.
        static func contentHeight(for tab: NotchTab) -> CGFloat {
            switch tab {
            case .clipboard: expandedContentHeight + 32
            // Le minuteur tient en une regle et une ligne de commandes :
            // l'etirer a la hauteur des widgets laisserait un grand vide.
            case .timer: 118
            // Plafond impose par `NotchWindowController.hostBandHeight` : au
            // dela, la fenetre hote tronquerait le panneau au lieu de grandir.
            case .calendar: 206
            default: expandedContentHeight
            }
        }

        /// Largeur utile des onglets qui ne se calent pas sur leur contenu.
        /// `scale` vient du reglage de largeur du panneau.
        static func contentWidth(for tab: NotchTab, scale: CGFloat = 1) -> CGFloat {
            let base: CGFloat = switch tab {
            case .clipboard: 980
            case .timer: 860
            case .tray: 900
            case .pocket: 900
            case .settings: 900
            case .calendar: 920
            default: defaultContentWidth
            }
            return base * scale
        }
        /// Plafond absolu du panneau etendu. Au-dela, il cesse d'etre un
        /// accessoire du notch et devient une fenetre qui masque le travail.
        /// L'appelant le borne en plus a une fraction de l'ecran, pour qu'un
        /// 13 pouces et un 16 pouces gardent la meme proportion.
        static let expandedMaxWidth: CGFloat = 1600
        /// Part maximale de la largeur d'ecran occupee par le panneau.
        static let maxScreenFraction: CGFloat = 0.94
        /// Largeur minimale : la barre d'onglets doit tenir sans se tasser.
        static let minimumPanelWidth: CGFloat = 600
        /// Largeur de repli pour les onglets qui n'ont pas encore de contenu.
        static let defaultContentWidth: CGFloat = 680
    }

    // MARK: Typographie
    //
    // La police reste celle du systeme — c'est le bon choix pour un utilitaire
    // qui vit contre la barre des menus, et une police tierce y jurerait. La
    // personnalite ne vient donc PAS du dessin des lettres mais de leur
    // TRAITEMENT : de minuscules capitales espacees (la nomenclature gravee
    // d'un appareil de mesure) contre de grands chiffres arrondis (le cadran).
    // C'est ce contraste, et lui seul, qui porte le ton.
    //
    // Quatre roles : `caption` pour les libelles graves, `display` arrondi pour
    // les valeurs, `body` pour les phrases, `data` monospace pour ce qui
    // s'aligne en colonne (horodatages, codes couleur).
    enum Typography {
        static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func body(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        static func data(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// Libelle grave. A employer AVEC `.textCase(.uppercase)` et le
        /// `tracking` ci-dessous — les trois vont ensemble, voir `engraved()`.
        static func caption(_ size: CGFloat = 9, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        /// Interlettrage des capitales gravees. En dessous de 9 pt, des
        /// capitales non espacees deviennent un pate illisible.
        static let engravedTracking: CGFloat = 0.8
    }

    // MARK: Mouvement
    //
    // Toutes les animations du panneau passent par ces trois courbes. C'est ce
    // qui rend « Reduire les animations » applicable en UN SEUL endroit : quand
    // la preference systeme est active, chaque courbe se replie sur un fondu
    // quasi instantane, et les 47 appels a `Theme.Motion.*` s'y conforment sans
    // qu'aucun ait a connaitre la preference. Les proprietes sont donc
    // CALCULEES, pas constantes : elles relisent la preference a chaque
    // animation, et un changement dans les Reglages Systeme prend effet a la
    // suivante, sans redemarrage.
    enum Motion {

        /// Preference « Reduire les animations » (Reglages Systeme >
        /// Accessibilite > Affichage). API publique, lue a la volee.
        @MainActor static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// Substitut sans mouvement : un fondu si court qu'il ne se lit pas
        /// comme un deplacement, mais assez present pour ne pas faire clignoter
        /// le contenu d'un cran a l'autre.
        private static let reduced = Animation.easeOut(duration: 0.12)

        /// Morph pilule → panneau. Ressort court, sans rebond visible :
        /// le verre doit paraitre dense, pas elastique.
        @MainActor static var morph: Animation {
            reduceMotion ? reduced : .spring(response: 0.34, dampingFraction: 0.82)
        }
        /// Retour au repli : legerement plus lent, le regard suit la fermeture.
        @MainActor static var collapse: Animation {
            reduceMotion ? reduced : .spring(response: 0.40, dampingFraction: 0.90)
        }
        /// Apparition/disparition d'une notification compacte.
        @MainActor static var island: Animation {
            reduceMotion ? reduced : .spring(response: 0.30, dampingFraction: 0.78)
        }
    }
}

// MARK: - GaugeTint
//
// Couleur des jauges de volume et de luminosite (lentille, badge, valeur).
// Reglable — voir QuickSettingsTabView — car l'ambre par defaut ne convient
// pas a tous les fonds de bureau ni a tous les gouts, et rien d'autre dans
// l'app n'a besoin de cette teinte.
enum GaugeTint: String, CaseIterable, Identifiable, Codable, Sendable {
    case ember
    case green
    case blue
    case purple
    case white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .ember: Theme.Palette.ember
        case .green: Color(red: 0.30, green: 0.85, blue: 0.45)
        case .blue: Color(red: 0.35, green: 0.60, blue: 1.0)
        case .purple: Color(red: 0.68, green: 0.45, blue: 1.0)
        case .white: .white
        }
    }

    var label: String {
        switch self {
        case .ember: "Orange"
        case .green: "Vert"
        case .blue: "Bleu"
        case .purple: "Violet"
        case .white: "Blanc"
        }
    }
}
