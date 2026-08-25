import Foundation
import Testing
@testable import RSnotch

// MARK: - Parsing de l'état de lecture
//
// La sortie brute d'un script d'etat : huit champs separes par l'unite ASCII
// 31. C'est la logique la plus fragile du pont musical — une derive du
// dictionnaire de scripting d'un lecteur y passerait inapercue. Ces tests
// fixent le contrat : huit champs exacts, ou etat vide.

@Suite("Parsing de l'état de lecture")
struct MediaParsingTests {

    private let sep = String(MusicScriptingService.separator)
    private let now = Date(timeIntervalSince1970: 1_000)

    private func parse(_ fields: [String]) -> NowPlayingSnapshot {
        MusicScriptingService.parseSnapshot(
            from: fields.joined(separator: sep), app: .spotify, capturedAt: now
        )
    }

    @Test("Huit champs valides donnent un instantané complet")
    func validEightFields() {
        let snap = parse(["playing", "Kill Bill", "SZA", "SOS", "153", "42", "1",
                          "https://example.com/art.jpg"])
        #expect(snap.state == .playing)
        #expect(snap.track?.title == "Kill Bill")
        #expect(snap.track?.artist == "SZA")
        #expect(snap.track?.album == "SOS")
        #expect(snap.track?.duration == 153)
        #expect(snap.position == 42)
        #expect(snap.track?.isLoved == true)
        #expect(snap.track?.artworkURL == URL(string: "https://example.com/art.jpg"))
    }

    @Test("« stopped » seul (un champ) donne un état vide, pas un plantage")
    func stoppedSingleField() {
        let snap = parse(["stopped"])
        #expect(snap.state == .stopped)
        #expect(snap.track == nil)
        #expect(snap.position == 0)
    }

    @Test("Un nombre de champs inattendu retombe sur l'état vide")
    func malformedFieldCount() {
        #expect(parse(["playing", "titre", "artiste"]).track == nil)   // trop peu
        #expect(parse(Array(repeating: "x", count: 12)).track == nil)  // trop
    }

    @Test("Un champ numérique illisible vaut zéro, sans casser le reste")
    func unreadableNumberFallsBackToZero() {
        // Position « missing value » : le reste du morceau doit survivre.
        let snap = parse(["playing", "Titre", "Artiste", "Album", "200",
                          "missing value", "0", ""])
        #expect(snap.position == 0)
        #expect(snap.track?.title == "Titre")
        #expect(snap.track?.duration == 200)
    }

    @Test("Une pochette vide ne produit pas d'URL")
    func emptyArtworkYieldsNilURL() {
        let snap = parse(["paused", "T", "A", "Al", "10", "0", "0", ""])
        #expect(snap.track?.artworkURL == nil)
        #expect(snap.state == .paused)
    }
}
