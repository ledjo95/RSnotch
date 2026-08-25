import AppKit
import Foundation

// MARK: - BookmarkStore
//
// Conserve l'acces a des fichiers choisis par l'utilisateur au-dela du
// lancement courant.
//
// HORS BAC A SABLE (depuis le 25 aout 2026), la portee de securite n'a plus
// d'objet : le systeme de fichiers n'est plus filtre, un bookmark ordinaire
// suffit a retrouver le fichier. Pire, `startAccessingSecurityScopedResource()`
// rend `false` hors sandbox — il n'y a aucune portee a ouvrir. Le code
// d'origine en faisait une condition de reussite : applique tel quel, il aurait
// fait echouer toute resolution, et les applications epinglees comme l'image de
// fond auraient disparu en silence au premier lancement.
//
// D'ou les deux regles de ce fichier :
//   1. l'ouverture de portee est CONSULTATIVE, jamais bloquante ;
//   2. la resolution tente le format scoped PUIS le format ordinaire, pour
//      relire les bookmarks ecrits du temps du bac a sable.
//
// Aucun acces n'est pris sans action explicite de l'utilisateur : la portee est
// strictement limitee aux fichiers qu'il a designes lui-meme.

@MainActor
final class BookmarkStore {

    static let shared = BookmarkStore()

    private let defaults: UserDefaults
    /// URLs dont l'acces scoped est ouvert, pour pouvoir le refermer proprement.
    private var openScopes: [String: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func storageKey(_ key: String) -> String { "bookmark.\(key)" }

    // MARK: Ecriture

    func save(_ url: URL, for key: String) throws {
        // `.withSecurityScope` reste demande en premier : le format est plus
        // riche et reste lisible hors sandbox. S'il est refuse, un bookmark
        // ordinaire fait tout aussi bien l'affaire ici.
        let data: Data
        if let scoped = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            data = scoped
        } else {
            data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(data, forKey: storageKey(key))
    }

    // MARK: Lecture

    /// Resout le bookmark et ouvre l'acces. L'acces reste ouvert jusqu'a
    /// `release(_:)` ou la fin du processus.
    func resolve(_ key: String) -> URL? {
        if let open = openScopes[key] { return open }
        guard let data = defaults.data(forKey: storageKey(key)) else { return nil }

        var isStale = false
        var resolved: URL?
        // Les deux formats, dans cet ordre : les bookmarks ecrits du temps du
        // bac a sable sont scoped, ceux ecrits depuis peuvent ne pas l'etre.
        for options in [URL.BookmarkResolutionOptions.withSecurityScope, []] {
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolved = url
                break
            }
        }
        guard let url = resolved else {
            // Bookmark illisible (fichier supprime, volume absent) : on le purge
            // plutot que de laisser l'UI retenter indefiniment.
            clear(key)
            return nil
        }

        // CONSULTATIF, jamais bloquant : hors bac a sable cet appel rend
        // toujours `false` faute de portee a ouvrir, et en faire une condition
        // de reussite ferait disparaitre tous les elements epingles.
        if url.startAccessingSecurityScopedResource() {
            openScopes[key] = url
        }

        // Le fichier a bouge : on reecrit le bookmark tant que l'acces est ouvert.
        if isStale { try? save(url, for: key) }
        return url
    }

    // MARK: Liberation

    func release(_ key: String) {
        openScopes.removeValue(forKey: key)?.stopAccessingSecurityScopedResource()
    }

    func clear(_ key: String) {
        release(key)
        defaults.removeObject(forKey: storageKey(key))
    }
}
