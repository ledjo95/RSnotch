import Foundation
import Testing
@testable import RSnotch

// MARK: - AppContainerTests
//
// `migratePreferences` a deja cause un bug reel : `launcher.items` et ses
// `bookmark.launch.*` ont ete repris de facon desynchronisee, laissant une
// grappe de tuiles vides. La regle "en bloc ou pas du tout" fixe ce
// probleme, mais sa condition de declenchement (`restored > 0` OU cle
// absente) est large : elle peut ecraser `launcher.items` cote neuf a cause
// d'une cle totalement sans rapport restauree en meme temps. Ces tests
// pinnent le comportement actuel, y compris ce cas piegeux.

@Suite("Migration des préférences")
@MainActor
struct AppContainerTests {

    private func makeSandboxContainer(with dictionary: [String: Any]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AppContainerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let prefsDir = root.appending(path: "Library/Preferences", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        let plist = prefsDir.appending(path: "com.varicube.RSnotch.plist", directoryHint: .notDirectory)
        try (dictionary as NSDictionary).write(to: plist)
        return root
    }

    private func makeIsolatedDefaults(_ name: String = #function) -> UserDefaults {
        let suiteName = "test.AppContainer.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Nouvelle clé absente : reprise directe")
    func newKeyRestored() throws {
        let container = try makeSandboxContainer(with: ["hud.gaugeTint": "purple"])
        let defaults = makeIsolatedDefaults()

        AppContainer.migratePreferences(from: container, defaults: defaults)

        #expect(defaults.string(forKey: "hud.gaugeTint") == "purple")
    }

    @Test("Clé déjà présente côté neuf : jamais écrasée")
    func existingKeyNotOverwritten() throws {
        let container = try makeSandboxContainer(with: ["hud.gaugeTint": "purple"])
        let defaults = makeIsolatedDefaults()
        defaults.set("blue", forKey: "hud.gaugeTint")

        AppContainer.migratePreferences(from: container, defaults: defaults)

        #expect(defaults.string(forKey: "hud.gaugeTint") == "blue")
    }

    @Test("launcher.items et bookmark.launch.* migrent en bloc quand absents")
    func coupledKeysMigrateTogether() throws {
        let container = try makeSandboxContainer(with: [
            "launcher.items": "stored-items-json",
            "bookmark.launch.uuid-1": "stored-bookmark-data"
        ])
        let defaults = makeIsolatedDefaults()

        AppContainer.migratePreferences(from: container, defaults: defaults)

        #expect(defaults.string(forKey: "launcher.items") == "stored-items-json")
        #expect(defaults.string(forKey: "bookmark.launch.uuid-1") == "stored-bookmark-data")
    }

    @Test("launcher.items écrase (overwrite) si une autre clé sans rapport a été reprise")
    func coupledKeysOverwriteOnUnrelatedRestore() throws {
        let container = try makeSandboxContainer(with: [
            "hud.gaugeTint": "purple",
            "launcher.items": "stored-items-json",
            "bookmark.launch.uuid-1": "stored-bookmark-data"
        ])
        let defaults = makeIsolatedDefaults()
        // Cote neuf : launcher.items existe deja et diffère de l'ancien —
        // mais "hud.gaugeTint" (sans rapport) est absent, donc `restored > 0`
        // se declenche et ecrase quand meme le bloc couple.
        defaults.set("local-items-json", forKey: "launcher.items")

        AppContainer.migratePreferences(from: container, defaults: defaults)

        #expect(defaults.string(forKey: "hud.gaugeTint") == "purple")
        #expect(defaults.string(forKey: "launcher.items") == "stored-items-json")
        #expect(defaults.string(forKey: "bookmark.launch.uuid-1") == "stored-bookmark-data")
    }

    @Test("Rien à reprendre : bloc couplé non touché si tout est déjà présent côté neuf")
    func coupledKeysUntouchedWhenNothingElseRestored() throws {
        let container = try makeSandboxContainer(with: [
            "hud.gaugeTint": "purple",
            "launcher.items": "stored-items-json",
            "bookmark.launch.uuid-1": "stored-bookmark-data"
        ])
        let defaults = makeIsolatedDefaults()
        defaults.set("blue", forKey: "hud.gaugeTint")
        defaults.set("local-items-json", forKey: "launcher.items")
        defaults.set("local-bookmark-data", forKey: "bookmark.launch.uuid-1")

        AppContainer.migratePreferences(from: container, defaults: defaults)

        #expect(defaults.string(forKey: "launcher.items") == "local-items-json")
        #expect(defaults.string(forKey: "bookmark.launch.uuid-1") == "local-bookmark-data")
    }
}
