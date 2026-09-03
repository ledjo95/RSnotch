import Foundation
import Testing
@testable import RSnotch

// MARK: - AppSettingsTests
//
// Chaque reglage enum d'AppSettings suit le meme pattern : rawValue String
// ecrit dans UserDefaults au `didSet`, relu via `flatMap(Enum.init(rawValue:))
// ?? default` a l'init. Ces tests pinnent ce pattern sur `gaugeTint` — le
// repli silencieux sur une valeur par defaut si la donnee stockee est
// corrompue/perimee, et l'absence de synchronisation entre deux instances
// qui partagent la meme UserDefaults (chacune ne lit qu'a son init).
//
// La cle litterale "hud.gaugeTint" duplique `AppSettings.Key.gaugeTint`
// (prive) : un futur renommage de cle fera echouer ce test de façon
// visible plutot que de casser silencieusement le round-trip en prod.

@Suite("Réglages persistés")
@MainActor
struct AppSettingsTests {

    private func isolatedDefaults(_ name: String = #function) -> UserDefaults {
        let suiteName = "test.AppSettings.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("gaugeTint : round-trip normal")
    func gaugeTintRoundTrip() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.gaugeTint = .purple

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.gaugeTint == .purple)
    }

    @Test("gaugeTint : valeur brute invalide retombe silencieusement sur .ember")
    func gaugeTintInvalidRawValueFallsBackToDefault() {
        let defaults = isolatedDefaults()
        defaults.set("not-a-real-tint", forKey: "hud.gaugeTint")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.gaugeTint == .ember)
    }

    @Test("Deux instances sur la même suite ne se synchronisent pas en direct")
    func noLiveSyncBetweenInstances() {
        let defaults = isolatedDefaults()
        let first = AppSettings(defaults: defaults)
        let second = AppSettings(defaults: defaults)

        first.gaugeTint = .blue

        #expect(second.gaugeTint == .ember)
        #expect(defaults.string(forKey: "hud.gaugeTint") == "blue")
    }
}
