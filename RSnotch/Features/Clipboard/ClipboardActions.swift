import AppKit
import Foundation
import SwiftData

// MARK: - ClipboardActions
//
// Operations sur une entree d'historique. Regroupees ici plutot que dispersees
// dans les vues : recopier une entree doit remettre exactement le meme type de
// donnee sur le presse-papiers, pas seulement sa representation texte.

@MainActor
struct ClipboardActions {

    let context: ModelContext

    /// Remet l'entree sur le presse-papiers. La capture qui suivra reconnaitra
    /// l'empreinte et remontera l'entree existante au lieu d'en creer une.
    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.kind {
        case .image:
            guard let image = entry.image else { return }
            pasteboard.writeObjects([image])
        case .file:
            guard let path = entry.text else { return }
            pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        case .text, .color:
            guard let text = entry.text else { return }
            pasteboard.setString(text, forType: .string)
        }
    }

    func toggleFavorite(_ entry: ClipboardEntry) {
        entry.isFavorite.toggle()
        try? context.save()
    }

    func delete(_ entry: ClipboardEntry) {
        context.delete(entry)
        try? context.save()
    }

    /// Vide l'historique en preservant les favoris : les epingler signifie
    /// vouloir les garder, y compris apres un grand menage.
    func clearAll(keepingFavorites: Bool = true) {
        let descriptor = FetchDescriptor<ClipboardEntry>()
        guard let entries = try? context.fetch(descriptor) else { return }
        for entry in entries where !(keepingFavorites && entry.isFavorite) {
            context.delete(entry)
        }
        try? context.save()
    }
}
