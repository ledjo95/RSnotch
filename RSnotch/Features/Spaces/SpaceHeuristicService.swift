import AppKit
import Foundation
import Observation
import OSLog

private let spaceLog = Logger(subsystem: "com.varicube.RSnotch", category: "spaces")

// MARK: - SpaceHeuristicService
//
// Reconnaissance des bureaux (« Spaces »), par heuristique.
//
// POURQUOI UNE HEURISTIQUE : macOS n'expose AUCUN identifiant public de Space.
// `CGSCopyManagedDisplaySpaces` en donnerait un, mais c'est un symbole prive —
// interdit sur le Mac App Store et casse a chaque version. Le seul signal
// public est `NSWorkspace.activeSpaceDidChangeNotification`, qui dit QUE le
// bureau a change, jamais LEQUEL.
//
// L'EMPREINTE : la liste des fenetres a l'ecran est lisible via
// `CGWindowListCopyWindowInfo`, API publique et sans entitlement. On ne garde
// que les PID proprietaires des fenetres de niveau normal : une app reste sur
// son bureau, alors que les numeros de fenetre changent des qu'on en ouvre ou
// ferme une. « Code + Terminal » identifie donc un bureau de facon bien plus
// stable que la liste de ses fenetres.
//
// Aucun titre de fenetre n'est lu : les titres exigeraient l'autorisation
// d'enregistrement de l'ecran, et RSnotch n'en a aucun besoin.
//
// LIMITES ASSUMEES, a documenter dans les Reglages :
//   — deux bureaux qui portent exactement les memes apps sont indiscernables ;
//   — deplacer une app d'un bureau a l'autre peut faire passer un bureau connu
//     pour un nouveau ;
//   — l'association bureau → teinte ne vaut que pour la session en cours si les
//     apps changent beaucoup.
// C'est un confort visuel, pas un mecanisme sur lequel reposer.

@MainActor
@Observable
final class SpaceHeuristicService {

    /// Index du bureau courant, dans l'ordre de premiere rencontre.
    private(set) var currentIndex: Int = 0
    /// Nombre de bureaux distincts rencontres depuis le lancement.
    private(set) var knownCount: Int = 1
    /// `false` si l'empreinte est illisible : l'app doit alors se taire plutot
    /// que d'attribuer des teintes au hasard.
    private(set) var isAvailable = true

    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// Empreintes connues, indexees par ordre de decouverte.
    @ObservationIgnored private var fingerprints: [Set<pid_t>] = []

    /// Part commune minimale entre deux empreintes pour les considerer comme le
    /// meme bureau. Trop haut, ouvrir une app cree un faux bureau ; trop bas,
    /// deux bureaux voisins se confondent.
    private let similarityThreshold = 0.6

    // MARK: Cycle de vie

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }

    // MARK: Heuristique

    private func evaluate() {
        evaluate(Self.fingerprint())
    }

    private func evaluate(_ candidate: Set<pid_t>?) {
        guard let fingerprint = candidate, !fingerprint.isEmpty else {
            // Un bureau vide (aucune fenetre) n'est pas identifiable : on reste
            // sur le dernier bureau connu plutot que d'en inventer un.
            isAvailable = !fingerprints.isEmpty
            spaceLog.notice("empreinte illisible ou bureau vide")
            return
        }
        isAvailable = true

        if let index = match(fingerprint) {
            // Le bureau evolue : on rafraichit son empreinte pour suivre les
            // apps qu'on y ouvre au fil de la session.
            fingerprints[index] = fingerprint
            currentIndex = index
        } else {
            fingerprints.append(fingerprint)
            currentIndex = fingerprints.count - 1
        }
        knownCount = fingerprints.count
        spaceLog.notice("bureau \(self.currentIndex + 1) sur \(self.knownCount)")
    }

    #if DEBUG
    /// Eprouve l'heuristique sur des empreintes controlees. Deux bureaux
    /// reellement distincts ne sont pas simulables : il faut plusieurs bureaux
    /// ET des apps differentes sur chacun. Ce banc verifie donc les deux
    /// proprietes qui comptent — la STABILITE (ouvrir une app ne cree pas un
    /// faux bureau) et la DISCRIMINATION (un jeu d'apps different en cree un).
    func runDebugScenario() {
        let cases: [(String, Set<pid_t>, Int)] = [
            ("bureau initial",            [101, 102, 103],      1),
            ("une app ouverte en plus",   [101, 102, 103, 104], 1),
            ("apps entierement autres",   [201, 202, 203],      2),
            ("retour au premier",         [101, 102, 103],      1)
        ]
        for (label, pids, expected) in cases {
            evaluate(pids)
            let got = currentIndex + 1
            spaceLog.notice(
                "banc — \(label, privacy: .public) : attendu \(expected), obtenu \(got) \(got == expected ? "OK" : "ECHEC", privacy: .public)"
            )
        }
    }

    /// Amene le service sur le n-ieme bureau, pour eprouver la teinte a l'oeil.
    func forceDebugIndex(_ index: Int) {
        for step in 0...max(0, index) {
            evaluate(Set((0...2).map { pid_t(1000 * (step + 1) + $0) }))
        }
    }

    #endif

    private func match(_ fingerprint: Set<pid_t>) -> Int? {
        var best: (index: Int, score: Double)?
        for (index, known) in fingerprints.enumerated() {
            let union = known.union(fingerprint).count
            guard union > 0 else { continue }
            let score = Double(known.intersection(fingerprint).count) / Double(union)
            if score >= similarityThreshold, score > (best?.score ?? 0) {
                best = (index, score)
            }
        }
        return best?.index
    }

    /// PID des applications possedant une fenetre visible sur le bureau courant.
    private static func fingerprint() -> Set<pid_t>? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var pids: Set<pid_t> = []
        for window in windows {
            // Niveau 0 = fenetre de document ordinaire. Ecarter les autres
            // retire la barre des menus, le Dock et les panneaux flottants —
            // qui sont presents sur TOUS les bureaux et ne distinguent rien.
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            // RSnotch est sur tous les bureaux : s'inclure fausserait la mesure.
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            pids.insert(pid)
        }
        return pids
    }
}
