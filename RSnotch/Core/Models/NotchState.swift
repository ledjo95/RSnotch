import CoreGraphics
import Foundation

// MARK: - NotchState
/// Les trois formes que peut prendre la fenetre du notch.
enum NotchState: Equatable, Sendable {
    /// Au repos : la forme epouse l'encoche, quasi invisible.
    case collapsed
    /// Notification breve : la forme s'elargit puis se retracte seule.
    case island(CompactIslandPayload)
    /// Panneau complet, ouvert au survol ou au clic.
    case expanded

    var isExpanded: Bool { self == .expanded }

    var islandPayload: CompactIslandPayload? {
        if case .island(let payload) = self { return payload }
        return nil
    }
}

// MARK: - CompactIslandPayload
/// Contenu d'une notification compacte. Volontairement minimal : un symbole,
/// deux lignes de texte, une teinte. Toute la mise en forme reste cote vue.
struct CompactIslandPayload: Equatable, Sendable, Identifiable {

    /// Ton de l'annonce. Le modele ne connait pas de couleur : il dit ce que la
    /// nouvelle VAUT, la vue decide comment le montrer.
    enum Emphasis: Sendable, Equatable {
        /// Information courante — morceau, appareil connecte.
        case routine
        /// Ce qui demande une action : batterie faible, minuteur termine.
        case alert
    }

    /// Niveau continu — volume, luminosite. Quand il est present, l'annonce se
    /// dessine en jauge plutot qu'en ligne de texte : une valeur qui varie se
    /// lit a la longueur d'une barre, pas a un nombre qui defile.
    struct Level: Equatable, Sendable {
        let value: Double
        /// Coupe : la jauge se dessine eteinte, meme si `value` n'est pas nul.
        /// Le systeme conserve en effet le volume choisi quand on coupe le son.
        let isMuted: Bool
        /// Affiche le pourcentage a cote de la jauge. Les deux sources sont
        /// desormais exactes — CoreAudio pour le volume, DisplayServices pour
        /// la luminosite — donc le chiffre est toujours affiche. Le drapeau
        /// reste pour une jauge future dont la valeur ne serait pas mesurable.
        let showsValue: Bool

        init(value: Double, isMuted: Bool = false, showsValue: Bool = true) {
            self.value = min(max(value, 0), 1)
            self.isMuted = isMuted
            self.showsValue = showsValue
        }
    }

    let id: UUID
    let symbolName: String
    let title: String
    let detail: String?
    let emphasis: Emphasis
    let level: Level?
    /// Duree d'affichage avant retraction automatique.
    let duration: Duration

    init(
        id: UUID = UUID(),
        symbolName: String,
        title: String,
        detail: String? = nil,
        emphasis: Emphasis = .routine,
        level: Level? = nil,
        duration: Duration = .seconds(2.6)
    ) {
        self.id = id
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.emphasis = emphasis
        self.level = level
        self.duration = duration
    }
}

// MARK: - NotchTab
/// Onglets du panneau etendu. L'ordre correspond a la barre du haut :
/// les quatre premiers a gauche, les deux derniers a droite.
enum NotchTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case tray
    case clipboard
    case timer
    case calendar
    case stats
    case pocket
    case settings

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .tray: "tray.fill"
        case .clipboard: "doc.on.doc.fill"
        case .timer: "timer"
        case .calendar: "calendar"
        case .stats: "gauge.with.dots.needle.50percent"
        case .pocket: "square.and.arrow.down.on.square.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Libelle VoiceOver.
    var accessibilityLabel: String {
        switch self {
        case .home: "Widgets"
        case .tray: "Partage et fichiers"
        case .clipboard: "Presse-papiers"
        case .timer: "Minuteur"
        case .calendar: "Agenda"
        case .stats: "Statistiques système"
        case .pocket: "Pocket"
        case .settings: "Reglages"
        }
    }

    /// Cet onglet sait-il recevoir un fichier venu du Finder ?
    /// La page principale le sait — sa grappe d'applications est une cible de
    /// depot a part entiere. Basculer vers les zones de depot depuis cette
    /// page-la ARRACHERAIT l'utilisateur a la cible qu'il visait.
    var acceptsFileDrop: Bool {
        switch self {
        case .home, .tray: true
        case .clipboard, .timer, .calendar, .stats, .pocket, .settings: false
        }
    }

    static let leading: [NotchTab] = [.home, .tray, .clipboard, .timer, .calendar, .stats]
    static let trailing: [NotchTab] = [.pocket, .settings]
}
