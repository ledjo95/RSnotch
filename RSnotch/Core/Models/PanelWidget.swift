import Foundation

// MARK: - WidgetKind
/// Types de widgets disponibles dans le panneau. L'ordre de `allCases` fixe
/// l'ordre du menu d'ajout.
enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case date
    case weather
    case music
    case timer
    case image
    case quote
    case apps

    var id: String { rawValue }

    /// Types indisponibles pour l'instant, retires partout : menu d'ajout,
    /// disposition par defaut, et dispositions deja enregistrees.
    ///
    /// La meteo n'a pas de source reelle — le widget afficherait le
    /// `MockWeatherProvider` (27 °C, Paris, en dur). Mieux vaut l'absence qu'une
    /// donnee fausse promise a l'utilisateur. Reactiver = cabler un
    /// `WeatherKitProvider` (capability `com.apple.developer.weatherkit` +
    /// localisation) PUIS retirer `.weather` de cet ensemble. C'est le seul
    /// point a toucher : le filtre s'applique aux trois entrees ci-dessous.
    static let unavailable: Set<WidgetKind> = [.weather]

    var isAvailable: Bool { !Self.unavailable.contains(self) }

    var title: String {
        switch self {
        case .date: "Date"
        case .weather: "Météo"
        case .music: "Musique"
        case .timer: "Minuteur"
        case .image: "Image"
        case .quote: "Citation"
        case .apps: "Applications"
        }
    }

    var symbolName: String {
        switch self {
        case .date: "calendar"
        case .weather: "cloud.sun.fill"
        case .music: "music.note"
        case .timer: "timer"
        case .image: "photo"
        case .quote: "text.quote"
        case .apps: "square.grid.2x2.fill"
        }
    }

    /// Tailles autorisees. Un widget Date n'a rien a gagner a s'etaler ;
    /// un widget Musique a besoin de place pour la pochette et les controles.
    var allowedSizes: [WidgetSize] {
        switch self {
        case .date, .timer: [.small]
        case .weather, .quote, .image: [.small, .medium]
        case .music: [.medium, .large]
        case .apps: [.small, .medium, .large]
        }
    }

    var defaultSize: WidgetSize {
        allowedSizes.first ?? .small
    }
}

// MARK: - WidgetSize
//
// Le panneau etendu est une bande : les widgets partagent la meme hauteur et ne
// varient qu'en largeur. Une grille 2D obligerait a diviser une hauteur deja
// contrainte (150 pt) et rendrait chaque carte illisible.

enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .small: 214
        case .medium: 344
        case .large: 474
        }
    }

    var label: String {
        switch self {
        case .small: "Compact"
        case .medium: "Moyen"
        case .large: "Large"
        }
    }
}

// MARK: - PanelWidget
/// Une carte posee dans la rangee. `id` est stable : c'est lui qui circule
/// pendant un glisser-deposer.
struct PanelWidget: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: WidgetKind
    var size: WidgetSize

    init(id: UUID = UUID(), kind: WidgetKind, size: WidgetSize? = nil) {
        self.id = id
        self.kind = kind
        self.size = size ?? kind.defaultSize
    }

    /// Largeur d'affichage. La grappe d'applications ne suit pas les largeurs
    /// generiques : elle se mesure en colonnes d'icones remplies, et `size` n'y
    /// fixe qu'un plafond. Reserver les colonnes du plafond laisserait un vide
    /// a droite tant que la grappe n'est pas pleine.
    /// `scale` vient du reglage de largeur du panneau. Il ne s'applique PAS a
    /// la grappe d'applications : sa largeur se mesure en colonnes de tuiles de
    /// taille fixe, et l'etirer n'ajouterait que du vide a droite.
    /// La grappe d'applications ne suit pas l'echelle (cf. `displayWidth`).
    /// Le calcul d'ajustement de la rangee doit la traiter a part.
    var scalesWithPanelWidth: Bool { kind != .apps }

    func displayWidth(appItemCount: Int, scale: CGFloat = 1) -> CGFloat {
        switch kind {
        case .apps:
            AppsGridMetrics.width(
                columns: AppsGridMetrics.columns(itemCount: appItemCount, size: size)
            )
        default:
            size.width * scale
        }
    }
}

extension PanelWidget {
    /// Disposition livree a la premiere ouverture : ce qu'on peut afficher sans
    /// demander la moindre autorisation a l'utilisateur.
    ///
    /// Ordre : minuteur, lecture en cours, applications, date, meteo. La largeur
    /// du panneau se cale sur ses cartes ; une rangee de trois widgets donnait
    /// une bande courte, sans rapport avec le bandeau pleine largeur attendu.
    ///
    /// Le filtre `isAvailable` retire les types sans source reelle (voir
    /// `WidgetKind.unavailable`) : la meteo mock ne s'affiche donc pas d'office.
    static var defaultLayout: [PanelWidget] {
        [
            PanelWidget(kind: .timer),
            PanelWidget(kind: .music, size: .large),
            PanelWidget(kind: .apps, size: .medium),
            PanelWidget(kind: .date),
            PanelWidget(kind: .weather, size: .medium)
        ].filter { $0.kind.isAvailable }
    }
}
