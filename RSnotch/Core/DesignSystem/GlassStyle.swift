import SwiftUI

// MARK: - GlassIntensity
//
// Reglage « intensite du verre » (§3.6), exprime avec les variantes standard de
// `Glass` plutot qu'avec un reglage de flou fait main. Chaque cran correspond a
// une variante documentee : on ne bricole ni l'opacite ni le blur, ce qui
// garantit que le materiau continue d'adapter sa lisibilite au contenu dessous.

enum GlassIntensity: String, CaseIterable, Identifiable, Sendable {
    /// Verre le plus transparent. Le fond de bureau reste largement lisible.
    case light
    /// Materiau Liquid Glass standard. Defaut.
    case regular
    /// Verre teinte sombre, proche du noir de l'encoche.
    case dense

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Léger"
        case .regular: "Standard"
        case .dense: "Dense"
        }
    }

    /// Materiau de la coquille du panneau pour cette intensite.
    func shellGlass(tintedBy accent: Color?) -> Glass {
        // `Glass.tint(_:)` REMPLACE la teinte, il ne s'y ajoute pas. Poser
        // l'accent de bureau par-dessus la variante dense effacait donc son
        // assombrissement : le panneau s'eclaircissait des qu'un bureau portait
        // une couleur, et le noir de l'encoche cessait d'etre respecte. Les
        // deux teintes sont melangees AVANT d'etre posees, en une seule.
        switch self {
        case .light:
            guard let accent else { return Glass.clear.interactive() }
            return Glass.clear.tint(accent.opacity(0.18)).interactive()

        case .regular:
            guard let accent else { return Glass.regular.interactive() }
            return Glass.regular.tint(accent.opacity(0.18)).interactive()

        case .dense:
            let ink = Theme.Palette.ink.opacity(0.55)
            guard let accent else { return Glass.regular.tint(ink).interactive() }
            // L'accent est ramene vers l'encre — mais pas trop : la teinte
            // doit permettre de RECONNAITRE un bureau d'un coup d'oeil, ce
            // qu'un lavis invisible ne fait pas. Le gros du signal reste porte
            // par le filament, qui prend lui aussi la couleur du bureau.
            let blended = accent.mix(with: Theme.Palette.ink, by: 0.45)
            return Glass.regular.tint(blended.opacity(0.55)).interactive()
        }
    }
}

// MARK: - PanelWidth
//
// Reglage de largeur du panneau (§3.9). Un facteur applique aux gabarits plutot
// que trois jeux de valeurs : les proportions internes restent identiques d'un
// cran a l'autre, seule l'echelle change.

enum PanelWidth: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .compact: 0.82
        case .standard: 1.0
        case .large: 1.22
        }
    }
}

// MARK: - PanelSurface
//
// Fond du panneau (§3.6). L'image utilisateur n'est pas un « theme » de plus :
// c'est une couche posee SOUS le verre, ce qui laisse le materiau faire son
// travail d'adaptation au lieu de le remplacer.

enum PanelSurface: Equatable, Sendable {
    /// Verre seul. La couleur du bureau transparait.
    case glass
    /// Verre teinte sombre : rendu proche de l'encoche native.
    case blackGlass
    /// Image utilisateur sous le verre, referencee par bookmark (Phase 3).
    case image(URL)

    var isImage: Bool { if case .image = self { true } else { false } }
}

// MARK: - Environnement
//
// Ces trois valeurs traversent toute l'app. Les composants du design system les
// lisent ; aucune vue de fonctionnalite n'a a les passer a la main.

extension EnvironmentValues {
    /// Intensite du verre choisie dans les Reglages.
    @Entry var glassIntensity: GlassIntensity = .dense
    /// Teinte d'accent du Space courant (Phase 9). `nil` = aucune teinte.
    @Entry var spaceAccent: Color? = nil
    /// Fond du panneau.
    @Entry var panelSurface: PanelSurface = .blackGlass

    /// Appele par toute cible de depot pendant qu'un fichier la survole, pour
    /// annuler le repli en attente. Passe par l'environnement plutot que par
    /// un parametre : la grappe d'applications est enfouie a trois niveaux
    /// sous le panneau, et la traversee polluerait chaque vue intermediaire.
    @Entry var notchDragActivity: () -> Void = {}

    /// Verrou d'ouverture du panneau. `true` a l'ouverture d'une vue posee hors
    /// de la coquille (sous-panneau de dossier), `false` a sa fermeture.
    @Entry var notchOpenLock: (Bool) -> Void = { _ in }
}
