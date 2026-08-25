import Foundation
import Testing
@testable import RSnotch

// MARK: - Similarité de Jaccard des bureaux
//
// Le cœur de la reconnaissance des bureaux (§3.10) : deux jeux de PID se
// ressemblent-ils assez pour être le même bureau ? Le seuil de décision (0.6)
// vit ailleurs ; ici on fixe la mesure elle-même, indépendamment de l'ordre
// des bureaux rencontrés.

@Suite("Similarité de Jaccard")
struct SpaceHeuristicTests {

    @Test("Ensembles identiques : similarité 1")
    func identical() {
        #expect(SpaceHeuristicService.jaccard([1, 2, 3], [1, 2, 3]) == 1.0)
    }

    @Test("Ensembles disjoints : similarité 0")
    func disjoint() {
        #expect(SpaceHeuristicService.jaccard([1, 2], [3, 4]) == 0.0)
    }

    @Test("Deux vides sont dissemblables, pas identiques")
    func bothEmpty() {
        // Un bureau sans fenêtre ne « ressemble » à rien : deux vides ne
        // doivent pas fusionner en un seul bureau.
        #expect(SpaceHeuristicService.jaccard([], []) == 0.0)
    }

    @Test("Recouvrement partiel : intersection sur union")
    func partial() {
        // {1,2,3} ∩ {2,3,4} = {2,3} ; ∪ = {1,2,3,4} → 2/4 = 0,5
        #expect(SpaceHeuristicService.jaccard([1, 2, 3], [2, 3, 4]) == 0.5)
        // Sous le seuil de 0,6 : ces deux bureaux seraient jugés distincts.
        #expect(SpaceHeuristicService.jaccard([1, 2, 3], [2, 3, 4]) < 0.6)
    }

    @Test("Un seul PID commun sur un grand ensemble reste faible")
    func weakOverlap() {
        // {1..5} ∩ {5..9} = {5} ; ∪ = {1..9} → 1/9 ≈ 0,111
        let score = SpaceHeuristicService.jaccard([1, 2, 3, 4, 5], [5, 6, 7, 8, 9])
        #expect(abs(score - 1.0 / 9.0) < 0.0001)
    }
}
