import SwiftUI

// MARK: - SpaceAccent
//
// Teintes attribuees aux bureaux, dans l'ordre de decouverte.
//
// Ce sont des TEINTES DE VERRE, pas des fonds : elles passent par
// `.glassEffect(.regular.tint(...))` et le materiau reste translucide. D'ou des
// couleurs volontairement peu saturees — un accent vif traverserait le verre et
// concurrencerait l'ambre, qui reste reserve a l'action primaire.
//
// La premiere entree est neutre : le bureau ou l'on travaille le plus souvent
// ne doit pas se mettre a crier au premier lancement. La couleur n'apparait
// qu'a partir du deuxieme bureau rencontre, c'est-a-dire quand elle sert
// vraiment a distinguer quelque chose.

enum SpaceAccent {

    static let palette: [Color?] = [
        nil,                                                  // bureau 1 : neutre
        Color(red: 0.36, green: 0.53, blue: 0.72),            // ardoise
        Color(red: 0.45, green: 0.62, blue: 0.50),            // sauge
        Color(red: 0.62, green: 0.45, blue: 0.66),            // prune
        Color(red: 0.74, green: 0.56, blue: 0.36),            // ambre brule
        Color(red: 0.44, green: 0.60, blue: 0.68)             // bleu givre
    ]

    /// Teinte du bureau d'index donne. Au-dela de la palette, on recommence :
    /// mieux vaut deux bureaux de meme couleur qu'une couleur inventee.
    static func color(for index: Int) -> Color? {
        guard index >= 0 else { return nil }
        return palette[index % palette.count]
    }

    static func label(for index: Int) -> String {
        "Bureau \(index + 1)"
    }
}
