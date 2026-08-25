import AppKit
import Foundation

// MARK: - AppIconLoader
//
// Cache d'icones d'applications. `NSWorkspace.icon(forFile:)` touche le disque
// et rend une image de taille arbitraire : sans cache, chaque redessin du
// panneau relirait le bundle. Les icones sont redimensionnees une fois a la
// taille d'affichage.
//
// Sandbox : l'URL vient d'un security-scoped bookmark deja resolu par
// BookmarkStore. Aucun parcours du disque n'est tente en dehors de ce que
// l'utilisateur a explicitement designe.

@MainActor
final class AppIconLoader {

    static let shared = AppIconLoader()

    private var cache: [String: NSImage] = [:]

    /// Taille de rendu des icones. Les tuiles font 42 pt ; on rend en 64 pt
    /// pour rester net sur un ecran Retina sans stocker l'icone 512.
    private let renderSize = NSSize(width: 64, height: 64)

    func icon(for item: LaunchItem) -> NSImage? {
        if let cached = cache[item.bookmarkKey] { return cached }

        guard let url = BookmarkStore.shared.resolve(item.bookmarkKey) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = renderSize
        cache[item.bookmarkKey] = icon
        return icon
    }

    /// Icones des premieres applications d'un dossier, pour son apercu 2×2.
    func previewIcons(for folder: LaunchItem, limit: Int = 4) -> [NSImage] {
        folder.children.prefix(limit).compactMap { icon(for: $0) }
    }

    func invalidate(_ item: LaunchItem) {
        cache.removeValue(forKey: item.bookmarkKey)
    }
}
