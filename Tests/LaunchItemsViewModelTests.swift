import Foundation
import Testing
@testable import RSnotch

// MARK: - LaunchItemsViewModelTests
//
// `move` a cause un bug reel : glisser une app hors d'un dossier echouait
// silencieusement, car la recherche ne regardait que le premier niveau.
// Le fix a introduit `removeItem(id:)` (racine + enfants de chaque dossier)
// et un filet de securite si la cible disparait pendant le glisser. Ces
// tests couvrent les deux, via les points d'entree publics `move(id:before:)`
// et `move(id:into:)` — `removeItem` reste prive, non teste directement.

@Suite("Réorganisation de la grappe de lancement")
@MainActor
struct LaunchItemsViewModelTests {

    private func makeViewModel(_ name: String = #function) -> LaunchItemsViewModel {
        let suiteName = "test.LaunchItems.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LaunchItemsViewModel(defaults: defaults)
    }

    /// `addApp` cree un security-scoped bookmark, qui exige un fichier reel
    /// sur le disque — un chemin fictif fait silencieusement echouer l'ajout.
    /// On simule un bundle .app par un simple dossier reel, temporaire.
    private func makeAppBundle(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LaunchItemsViewModelTests-\(UUID().uuidString)/\(name).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("move(id:before:) sort une application d'un dossier vers la racine")
    func moveOutOfFolder() throws {
        let model = makeViewModel()
        model.addFolder()
        let folder = model.items[0]

        model.addApp(at: try makeAppBundle(named: "Foo"))
        let app = model.items.first { $0.appPath != nil }!
        #expect(model.move(id: app.id, into: folder))

        let folderAfterMove = model.items.first { $0.id == folder.id }!
        #expect(folderAfterMove.children.contains { $0.id == app.id })

        // Glisse hors du dossier, avant `other` (ajoutee apres pour servir de cible).
        model.addApp(at: try makeAppBundle(named: "Bar"))
        let target = model.items.first { $0.appPath?.hasSuffix("Bar.app") == true }!

        #expect(model.move(id: app.id, before: target))

        let folderAfterExtract = model.items.first { $0.id == folder.id }!
        #expect(!folderAfterExtract.children.contains { $0.id == app.id })
        #expect(model.items.contains { $0.id == app.id && !$0.isFolder })
    }

    @Test("move(id:before:) : cible disparue pendant le glisser, l'élément est ajouté en fin de liste")
    func moveTargetGoneFallsBackToAppend() throws {
        let model = makeViewModel()
        model.addApp(at: try makeAppBundle(named: "Foo"))
        let moved = model.items[0]
        // Cible fabriquee separement : son id n'existe pas dans `model.items`,
        // ce qui simule une disparition concurrente (ex. suppression pendant
        // le glisser).
        let ghostTarget = LaunchItem.app(url: URL(fileURLWithPath: "/Applications/Ghost.app"))

        let result = model.move(id: moved.id, before: ghostTarget)

        #expect(result == false)
        #expect(model.items.last?.id == moved.id)
        #expect(model.items.contains { $0.id == moved.id })
    }

    @Test("move(id:into:) déplace une application d'un dossier vers un autre")
    func moveBetweenFolders() throws {
        let model = makeViewModel()
        model.addFolder()
        model.addFolder()
        let firstFolder = model.items[0]
        let secondFolder = model.items[1]
        model.addApp(at: try makeAppBundle(named: "Foo"))
        let app = model.items.first { $0.appPath != nil }!

        #expect(model.move(id: app.id, into: firstFolder))
        #expect(model.items.first { $0.id == firstFolder.id }!.children.contains { $0.id == app.id })

        #expect(model.move(id: app.id, into: secondFolder))

        let firstAfter = model.items.first { $0.id == firstFolder.id }!
        let secondAfter = model.items.first { $0.id == secondFolder.id }!
        #expect(!firstAfter.children.contains { $0.id == app.id })
        #expect(secondAfter.children.contains { $0.id == app.id })
    }

    @Test("move(id:into:) refuse un dossier comme charge utile")
    func moveFolderIntoFolderRejected() {
        let model = makeViewModel()
        model.addFolder()
        model.addFolder()
        let target = model.items[0]
        let payloadFolder = model.items[1]

        let result = model.move(id: payloadFolder.id, into: target)

        #expect(result == false)
        #expect(model.items.first { $0.id == target.id }!.children.isEmpty)
    }
}
