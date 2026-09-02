import AppKit
import Foundation
import Observation

// MARK: - LaunchItemsViewModel
//
// Applications et dossiers epingles. Comme la disposition des widgets, la liste
// est courte et ordonnee : JSON dans UserDefaults. Les fichiers eux-memes sont
// atteints par security-scoped bookmarks (BookmarkStore) — c'est la seule
// facon, en sandbox, de relancer une application choisie lors d'une session
// precedente.

@MainActor
@Observable
final class LaunchItemsViewModel {

    private static let storageKey = "launcher.items"

    private(set) var items: [LaunchItem] = []
    /// Derniere erreur de lancement, affichee dans le panneau puis effacee.
    private(set) var lastError: String?

    private let defaults: UserDefaults

    // MARK: Cycle de vie

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([LaunchItem].self, from: data) {
            items = stored
        }
    }

    // MARK: Ajout

    /// Enregistre l'acces au bundle AVANT d'ajouter l'element : sans bookmark
    /// valide, l'icone et le lancement echoueraient au prochain demarrage.
    @discardableResult
    func addApp(at url: URL) -> Bool {
        let item = LaunchItem.app(url: url)
        do {
            try BookmarkStore.shared.save(url, for: item.bookmarkKey)
        } catch {
            lastError = "Impossible de mémoriser l’accès à \(item.name)."
            return false
        }
        items.append(item)
        persist()
        return true
    }

    func addApps(at urls: [URL]) {
        for url in urls where url.pathExtension == "app" {
            addApp(at: url)
        }
    }

    /// Repartit un depot venu du Finder : les bundles deviennent des raccourcis,
    /// les dossiers des dossiers de la grappe. Rend le nombre d'elements ajoutes.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        var ignored: [String] = []

        for url in urls {
            // Un bundle .app EST un dossier : l'extension tranche d'abord.
            if url.pathExtension == "app" {
                if addApp(at: url) { added += 1 }
            } else if isDirectory(url) {
                if addDirectory(at: url) { added += 1 }
            } else {
                ignored.append(url.lastPathComponent)
            }
        }

        if added == 0, !ignored.isEmpty {
            lastError = "La grappe n’accepte que des applications et des dossiers."
        }
        return added
    }

    /// Dossier du Finder depose sur la grappe. Il est epingle TEL QUEL : un
    /// clic l'ouvre dans le Finder.
    ///
    /// Volontairement distinct du groupe de raccourcis (`addFolder()`), qui
    /// n'existe que dans l'app. Convertir un dossier reel en groupe d'apps —
    /// ce que faisait la version precedente — perdait l'emplacement d'origine
    /// et ne rendait rien pour un dossier de documents.
    @discardableResult
    func addDirectory(at url: URL) -> Bool {
        let item = LaunchItem.directory(url: url)
        do {
            try BookmarkStore.shared.save(url, for: item.bookmarkKey)
        } catch {
            lastError = "Impossible de mémoriser l’accès à \(item.name)."
            return false
        }
        items.append(item)
        persist()
        return true
    }

    /// Dossier vide, cree a la main depuis le menu contextuel.
    func addFolder() {
        items.append(.folder())
        persist()
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    // MARK: Modification

    func rename(_ item: LaunchItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(item.id) { $0.name = trimmed }
    }

    /// Retire l'element et libere ses bookmarks. Vider le bookmark evite de
    /// laisser des acces ouverts sur des applications que l'utilisateur ne
    /// reference plus — un point que la revue App Store regarde.
    func remove(_ item: LaunchItem) {
        releaseBookmarks(of: item)
        items.removeAll { $0.id == item.id }
        for index in items.indices where items[index].isFolder {
            var children = items[index].children
            children.removeAll { $0.id == item.id }
            items[index].payload = .folder(children: children)
        }
        persist()
    }

    // MARK: Reorganisation

    @discardableResult
    func move(id: UUID, before target: LaunchItem) -> Bool {
        guard id != target.id, let moved = removeItem(id: id) else { return false }
        guard let to = items.firstIndex(where: { $0.id == target.id }) else {
            // La cible a disparu (retrait concurrent) : l'element retire ne
            // doit pas se perdre, on le repose en fin de rangee.
            items.append(moved)
            persist()
            return false
        }
        items.insert(moved, at: to)
        persist()
        return true
    }

    /// Depose une application dans un dossier — que l'application vienne de
    /// la rangee principale ou d'un AUTRE dossier (glisser d'un groupe a
    /// l'autre directement, sans repasser par la rangee).
    @discardableResult
    func move(id: UUID, into folder: LaunchItem) -> Bool {
        // Un groupe ne contient QUE des applications : y ranger un dossier du
        // Finder ou un autre groupe produirait une imbrication que le
        // sous-panneau ne sait pas afficher.
        guard folder.isFolder, id != folder.id,
              let moved = removeItem(id: id), moved.appPath != nil
        else { return false }

        guard let target = items.firstIndex(where: { $0.id == folder.id }) else {
            items.append(moved)
            persist()
            return false
        }
        items[target].payload = .folder(children: items[target].children + [moved])
        persist()
        return true
    }

    /// Retire un element de la liste, qu'il soit au premier niveau ou niche
    /// dans un dossier, et le rend. Point d'entree commun pour le glisser-
    /// deposer : la vue ne sait pas — et n'a pas a savoir — d'ou vient l'ID
    /// qu'on lui depose dessus.
    private func removeItem(id: UUID) -> LaunchItem? {
        if let index = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: index)
        }
        for index in items.indices where items[index].isFolder {
            var children = items[index].children
            guard let childIndex = children.firstIndex(where: { $0.id == id }) else { continue }
            let child = children.remove(at: childIndex)
            items[index].payload = .folder(children: children)
            return child
        }
        return nil
    }

    /// Ressort une application d'un dossier vers la rangee principale.
    func extract(_ child: LaunchItem, from folder: LaunchItem) {
        guard let folderIndex = items.firstIndex(where: { $0.id == folder.id }) else { return }
        var children = items[folderIndex].children
        children.removeAll { $0.id == child.id }
        items[folderIndex].payload = .folder(children: children)
        items.append(child)
        persist()
    }

    // MARK: Lancement

    func launch(_ item: LaunchItem) {
        guard let url = BookmarkStore.shared.resolve(item.bookmarkKey) else {
            lastError = "\(item.name) est introuvable."
            return
        }
        // Un dossier n'est pas une application : `openApplication` echouerait.
        // `open(_:)` le confie au Finder, qui est le comportement attendu.
        if item.isDirectory {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if !NSWorkspace.shared.open(url) {
                lastError = "Impossible d’ouvrir \(item.name)."
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                self.lastError = "Impossible d’ouvrir \(item.name) : \(error.localizedDescription)"
            }
        }
    }

    func clearError() { lastError = nil }

    // MARK: Interne

    private func update(_ id: UUID, _ transform: (inout LaunchItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[index])
        persist()
    }

    private func releaseBookmarks(of item: LaunchItem) {
        BookmarkStore.shared.clear(item.bookmarkKey)
        AppIconLoader.shared.invalidate(item)
        for child in item.children {
            BookmarkStore.shared.clear(child.bookmarkKey)
            AppIconLoader.shared.invalidate(child)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
