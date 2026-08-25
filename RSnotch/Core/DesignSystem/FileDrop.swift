import OSLog
import SwiftUI
import UniformTypeIdentifiers

// Trace du chemin de depot. Consultable avec :
//   log stream --predicate 'subsystem == "com.varicube.RSnotch"'
private let dropLog = Logger(subsystem: "com.varicube.RSnotch", category: "filedrop")

// MARK: - Mode de recuperation
//
// Deux facons de recuperer un fichier depose, selon ce qu'on veut en faire.

enum FileDropMode {
    /// Renvoie l'URL du fichier d'origine, telle que l'expediteur l'a publiee.
    /// Pour les usages qui doivent DESIGNER le fichier la ou il est : epingler
    /// une application, ouvrir la feuille AirDrop.
    case reference

    /// Materialise une copie dans le conteneur de l'app AVANT de rendre la
    /// main, et renvoie l'URL de cette copie.
    ///
    /// C'est la seule voie fiable quand le fichier doit etre conserve. En
    /// sandbox, l'acces accorde par un glisser vaut pour l'operation en cours :
    /// lire l'original apres coup — donc apres la fin du glisser — echoue
    /// silencieusement. La copie se fait donc DANS le rappel de chargement,
    /// pendant que l'acces tient encore.
    case materialized
}

// MARK: - Depot de fichiers
//
// `dropDestination(for: URL.self)` ne recoit pas de maniere fiable les fichiers
// venus du Finder : celui-ci publie un `public.file-url` brut, que la
// conformite `Transferable` d'`URL` ne decode pas systematiquement — le survol
// s'allume, mais le lacher n'appelle jamais l'action. On passe donc par
// `onDrop`, qui livre les `NSItemProvider` tels quels.
//
// Concurrence : `NSItemProvider` n'est pas `Sendable` et ne traverse jamais de
// frontiere d'acteur. Chaque fournisseur reste dans le callback ; seules des
// URLs — sendable — en sortent, via un collecteur protege par verrou qui ne
// delivre qu'une fois tous les fichiers resolus.

extension View {

    /// Cible de depot pour des fichiers.
    /// - Parameters:
    ///   - mode: voir `FileDropMode`.
    ///   - isTargeted: passe a `true` tant qu'un depot survole la vue.
    ///   - perform: recoit les URLs, sur l'acteur principal.
    func fileDropDestination(
        mode: FileDropMode = .reference,
        isTargeted: Binding<Bool>,
        perform: @escaping @MainActor @Sendable ([URL]) -> Void
    ) -> some View {
        onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            guard !providers.isEmpty else { return false }

            dropLog.debug("dépôt reçu : \(providers.count) élément(s), mode \(String(describing: mode))")

            let collector = DropCollector(expected: providers.count) { urls in
                dropLog.debug("livraison de \(urls.count) URL(s)")
                Task { @MainActor in perform(urls) }
            }

            for provider in providers {
                switch mode {
                case .reference:
                    _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                        collector.add(
                            data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        )
                    }

                case .materialized:
                    // `loadFileRepresentation(for: .fileURL)` serait une erreur
                    // ici : il reclame un fichier dont le CONTENU est une URL,
                    // pas le fichier depose. On decode donc l'URL, puis on
                    // copie sans attendre — a l'interieur du rappel, tant que
                    // l'acces accorde par le glisser tient encore.
                    _ = provider.loadDataRepresentation(for: .fileURL) { data, error in
                        guard let data,
                              let url = URL(dataRepresentation: data, relativeTo: nil)
                        else {
                            dropLog.error(
                                "URL indecodable (\(error?.localizedDescription ?? "aucune donnée"))"
                            )
                            collector.add(nil)
                            return
                        }
                        collector.add(DropInbox.materialize(url))
                    }
                }
            }
            return true
        }
    }
}

// MARK: - DropInbox
//
// Sas de reception. Les fichiers deposes y sont copies immediatement, puis
// repris par le service qui les consomme (la Pocket les deplace chez elle).
// Le dossier est vide au demarrage : rien n'y sejourne.

enum DropInbox {

    private static let directoryName = "DropInbox"

    static var directory: URL? {
        let manager = FileManager.default
        guard let support = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let inbox = support.appending(path: directoryName, directoryHint: .isDirectory)
        if !manager.fileExists(atPath: inbox.path) {
            try? manager.createDirectory(at: inbox, withIntermediateDirectories: true)
        }
        return inbox
    }

    /// Copie `source` dans le sas et renvoie l'URL de la copie.
    /// Appelable depuis n'importe quelle file : `FileManager` est sur.
    static func materialize(_ source: URL) -> URL? {
        guard let directory else {
            dropLog.error("sas indisponible")
            return nil
        }

        // L'acces accorde par un glisser passe par Powerbox : il faut l'ouvrir
        // explicitement avant de lire, et le refermer ensuite.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        // Un sous-dossier par depot : deux fichiers homonymes deposes ensemble
        // ne doivent pas s'ecraser, et le nom d'origine doit etre preserve.
        let slot = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let destination = slot.appending(path: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            dropLog.debug("copié : \(source.lastPathComponent)")
            return destination
        } catch {
            dropLog.error(
                "copie impossible de \(source.path) : \(error.localizedDescription)"
            )
            try? FileManager.default.removeItem(at: slot)
            return nil
        }
    }

    static func empty() {
        guard let directory else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - DropCollector
//
// Rassemble les URLs resolues et ne livre qu'une fois le dernier fournisseur
// traite — sans quoi un depot de trois fichiers declencherait trois traitements
// separes. Les rappels arrivent sur des files quelconques, d'ou le verrou.

private final class DropCollector: @unchecked Sendable {

    private let lock = NSLock()
    private var urls: [URL] = []
    private var remaining: Int
    private let deliver: @Sendable ([URL]) -> Void

    init(expected: Int, deliver: @escaping @Sendable ([URL]) -> Void) {
        self.remaining = expected
        self.deliver = deliver
    }

    func add(_ url: URL?) {
        lock.lock()
        if let url { urls.append(url) }
        remaining -= 1
        let isComplete = remaining == 0
        let snapshot = urls
        lock.unlock()

        guard isComplete, !snapshot.isEmpty else { return }
        deliver(snapshot)
    }
}
