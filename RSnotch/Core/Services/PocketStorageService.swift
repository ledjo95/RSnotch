import AppKit
import Foundation
import OSLog
import Observation

private let pocketLog = Logger(subsystem: "com.varicube.RSnotch", category: "pocket")

// MARK: - PocketItem
/// Un fichier depose dans la Pocket. L'URL pointe vers une COPIE rangee dans le
/// conteneur de l'app : l'original reste ou l'utilisateur l'a laisse, et rien
/// ne casse s'il le deplace ensuite.
struct PocketItem: Identifiable, Equatable, Sendable {
    /// Le chemin fait un identifiant stable d'un releve a l'autre. Un UUID tire
    /// a chaque rafraichissement casserait les animations de liste.
    var id: String { url.path }
    let url: URL
    let addedAt: Date
    let byteCount: Int
    /// Identifiant du depot dont ce fichier fait partie.
    let batchID: String

    var name: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

// MARK: - PocketBatch
//
// Un DEPOT, pas un fichier. Lacher trois fichiers selectionnes ensemble depuis
// le Finder produit un seul lot : les reprendre doit rendre les trois, d'un
// seul geste. Un fichier lache seul forme un lot d'un seul element et se
// comporte exactement comme avant.
//
// Le groupement tient a la STRUCTURE SUR DISQUE — un sous-dossier par depot —
// et non a un fichier d'index parallele : il survit donc au redemarrage sans
// rien a synchroniser, et un dossier vide ne peut pas survivre a ses fichiers.

struct PocketBatch: Identifiable, Equatable, Sendable {
    let id: String
    let items: [PocketItem]

    var urls: [URL] { items.map(\.url) }
    var isSingle: Bool { items.count == 1 }
    var addedAt: Date { items.map(\.addedAt).max() ?? .distantPast }
    var byteCount: Int { items.reduce(0) { $0 + $1.byteCount } }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var title: String {
        isSingle ? (items.first?.name ?? "") : "\(items.count) fichiers"
    }
}

// MARK: - PocketStorageService
//
// Rangement temporaire de fichiers.
//
// Sandbox : les copies vivent dans Application Support du conteneur de l'app —
// un emplacement toujours accessible en ecriture, sans aucun entitlement.
//
// La LECTURE du fichier d'origine est couverte par
// `com.apple.security.files.user-selected.read-only`, deja declare : un depot
// venu du Finder vaut designation explicite par l'utilisateur. La version
// read-WRITE n'est PAS necessaire — l'app ne modifie jamais le fichier source,
// elle le copie puis relache l'acces. Demander plus large serait un entitlement
// injustifiable en revue.

@MainActor
@Observable
final class PocketStorageService {

    /// Lots, du plus recent au plus ancien. C'est l'unite manipulee par l'UI.
    private(set) var batches: [PocketBatch] = []
    /// Tous les fichiers, a plat. Sert au comptage et a l'envoi groupe.
    var items: [PocketItem] { batches.flatMap(\.items) }
    private(set) var lastError: String?

    private let fileManager = FileManager.default

    /// Dossier de rangement. Cree a la demande.
    ///
    /// Passe par `AppContainer` : hors bac a sable,
    /// `applicationSupportDirectory` rend le dossier PARTAGE de l'utilisateur,
    /// et y creer un « Pocket » a la racine serait un squat.
    private var directory: URL? {
        AppContainer.directory(named: "Pocket")
    }

    // MARK: Cycle de vie

    /// `emptyOnLaunch` applique le reglage « vider au demarrage » : la Pocket
    /// est un sas, pas un dossier d'archives.
    func load(emptyOnLaunch: Bool) {
        if emptyOnLaunch {
            clear()
            return
        }
        migrateLooseFiles()
        refresh()
    }

    /// Les versions precedentes rangeaient les fichiers a plat. Chacun devient
    /// son propre lot, une fois pour toutes : sans cette migration, il faudrait
    /// porter deux dispositions sur disque indefiniment.
    private func migrateLooseFiles() {
        guard let directory else { return }
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            guard !isDirectory else { continue }
            let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: entry, to: folder.appending(path: entry.lastPathComponent))
        }
    }

    private func refresh() {
        guard let directory else { return }
        let folders = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        batches = folders.compactMap { folder -> PocketBatch? in
            let isDirectory = (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            guard isDirectory else { return nil }

            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            let files = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []

            let batchID = folder.lastPathComponent
            let items = files.map { url -> PocketItem in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return PocketItem(
                    url: url,
                    addedAt: values?.contentModificationDate ?? .now,
                    byteCount: values?.fileSize ?? 0,
                    batchID: batchID
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            // Un dossier vide est un residu : il ne doit pas s'afficher comme
            // un lot fantome.
            guard !items.isEmpty else {
                try? fileManager.removeItem(at: folder)
                return nil
            }
            return PocketBatch(id: batchID, items: items)
        }
        .sorted { $0.addedAt > $1.addedAt }
    }

    // MARK: Depot

    /// Range des fichiers dans la Pocket.
    /// - Parameter movingSource: `true` quand les URLs viennent du sas de
    ///   reception (`DropInbox`), qui appartient deja a l'app : on deplace au
    ///   lieu de copier, ce qui vide le sas au passage. `false` pour un fichier
    ///   designe ailleurs, dont l'original ne doit pas bouger.
    @discardableResult
    func add(_ sources: [URL], movingSource: Bool = false) -> Int {
        guard let directory else {
            lastError = "Dossier Pocket inaccessible."
            return 0
        }

        // Un dossier par depot : c'est lui qui porte le groupement. Les fichiers
        // laches ensemble depuis le Finder arrivent en un seul appel, donc dans
        // un seul dossier — et se reprennent ensemble.
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            lastError = "Dossier Pocket inaccessible."
            return 0
        }

        var added = 0
        var failures: [String] = []

        for source in sources {
            // Couvre le cas d'une URL issue d'un bookmark. Sans effet — et sans
            // dommage — sur un fichier deja dans le conteneur de l'app.
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let destination = uniqueDestination(for: source.lastPathComponent, in: folder)
            do {
                if movingSource {
                    try fileManager.moveItem(at: source, to: destination)
                    // Le sas cree un sous-dossier par depot : il devient vide.
                    try? fileManager.removeItem(at: source.deletingLastPathComponent())
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                }
                added += 1
            } catch {
                failures.append(source.lastPathComponent)
            }
        }

        lastError = failures.isEmpty
            ? nil
            : "Impossible de ranger \(failures.joined(separator: ", "))."

        if added > 0 {
            refresh()
        } else {
            try? fileManager.removeItem(at: folder)
        }
        return added
    }

    /// Evite d'ecraser un fichier de meme nom : « note.txt », « note 2.txt »…
    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        var candidate = directory.appending(path: name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        repeat {
            let suffixed = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appending(path: suffixed)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    // MARK: Retrait

    func remove(_ item: PocketItem) {
        try? fileManager.removeItem(at: item.url)
        // Le dossier du lot disparait avec son dernier fichier : sinon la Pocket
        // se remplirait de coquilles vides.
        removeFolderIfEmpty(at: item.url.deletingLastPathComponent())
        refresh()
    }

    /// Retire un depot entier.
    func remove(_ batch: PocketBatch) {
        guard let directory else { return }
        try? fileManager.removeItem(at: directory.appending(path: batch.id))
        refresh()
    }

    private func removeFolderIfEmpty(at folder: URL) {
        let remaining = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard remaining.isEmpty else { return }
        try? fileManager.removeItem(at: folder)
    }

    func clear() {
        guard let directory else { return }
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
        batches = []
    }

    func clearError() { lastError = nil }
}

// MARK: - AirDropSender
//
// Envoi par AirDrop. `NSSharingService` presente la feuille systeme : c'est
// elle qui choisit le destinataire, l'app ne voit jamais la liste des appareils
// a proximite et n'a donc besoin d'aucun acces reseau ni Bluetooth.

@MainActor
enum AirDropSender {

    static var isAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    /// Renvoie `false` si le service refuse les elements (fichier illisible,
    /// AirDrop indisponible sur la machine).
    @discardableResult
    static func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else { return false }

        service.perform(withItems: urls)
        return true
    }
}
