import AppKit
import Foundation
import SwiftData

// MARK: - ClipboardKind
/// Type detecte d'une entree. Stocke en chaine : SwiftData ne sait pas indexer
/// un enum, et une chaine reste lisible si le schema doit migrer.
enum ClipboardKind: String, Codable, CaseIterable, Sendable {
    case text
    case color
    case image
    case file

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

// MARK: - ClipboardFilter
/// Onglets de filtre du panneau.
enum ClipboardFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case recent
    case images
    case colors
    case text
    case files
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Récents"
        case .images: "Images"
        case .colors: "Couleurs"
        case .text: "Texte"
        case .files: "Fichiers"
        case .favorites: "Favoris"
        }
    }

    /// Type correspondant, ou `nil` pour les filtres transverses.
    var kind: ClipboardKind? {
        switch self {
        case .images: .image
        case .colors: .color
        case .text: .text
        case .files: .file
        case .recent, .favorites: nil
        }
    }
}

// MARK: - ClipboardEntry
//
// Une capture du presse-papiers. Tout reste dans le conteneur sandbox de
// l'app : aucune entree ne quitte l'appareil, et rien n'est synchronise.
//
// Les donnees binaires (image, icone de l'app source) sont marquees
// `.externalStorage` : SwiftData les ecrit alors en fichiers separes plutot que
// de gonfler la base, ce qui garde les requetes de liste rapides meme avec
// deux cents captures d'ecran en historique.

@Model
final class ClipboardEntry {

    /// Identifiant stable, utilise par l'UI et le glisser-deposer.
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var isFavorite: Bool

    /// `ClipboardKind.rawValue`.
    var kindRaw: String

    /// Contenu textuel : le texte lui-meme, le code couleur, ou le chemin du
    /// fichier selon le type.
    var text: String?

    @Attribute(.externalStorage) var imageData: Data?

    /// Identifiant et icone de l'application d'ou vient la copie. L'icone est
    /// capturee au moment de la copie : la resoudre plus tard supposerait un
    /// acces au bundle que le sandbox n'accorde pas.
    var sourceBundleID: String?
    @Attribute(.externalStorage) var sourceIconData: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        kind: ClipboardKind,
        text: String? = nil,
        imageData: Data? = nil,
        sourceBundleID: String? = nil,
        sourceIconData: Data? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRaw = kind.rawValue
        self.text = text
        self.imageData = imageData
        self.sourceBundleID = sourceBundleID
        self.sourceIconData = sourceIconData
        self.isFavorite = isFavorite
    }

    // MARK: Derives

    var kind: ClipboardKind {
        ClipboardKind(rawValue: kindRaw) ?? .text
    }

    var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }

    var sourceIcon: NSImage? {
        sourceIconData.flatMap(NSImage.init(data:))
    }

    /// Couleur decodee pour les entrees de type `.color`.
    var color: NSColor? {
        guard kind == .color, let text else { return nil }
        return NSColor(hex: text)
    }

    /// Empreinte servant a ne pas enregistrer deux fois la meme copie.
    var fingerprint: String {
        switch kind {
        case .image: "image:\(imageData?.count ?? 0):\(imageData?.hashValue ?? 0)"
        default: "\(kindRaw):\(text ?? "")"
        }
    }
}

// MARK: - Detection de couleur
extension NSColor {
    /// Decode `#RGB`, `#RRGGBB` ou `#RRGGBBAA`. Renvoie `nil` si la chaine
    /// n'est pas exactement un code couleur — un texte qui contient un code
    /// parmi d'autres mots reste du texte.
    convenience init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = String(trimmed.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        let expanded: String
        switch digits.count {
        case 3: expanded = digits.map { "\($0)\($0)" }.joined() + "FF"
        case 6: expanded = digits + "FF"
        case 8: expanded = digits
        default: return nil
        }

        guard let value = UInt32(expanded, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
            green: CGFloat((value >> 16) & 0xFF) / 255,
            blue: CGFloat((value >> 8) & 0xFF) / 255,
            alpha: CGFloat(value & 0xFF) / 255
        )
    }
}
