import SwiftUI

// MARK: - GlassSegmentedRow
//
// Rangee de filtres en pilules (Recents / Images / Couleurs…).
//
// Aucune pilule ne porte de verre — voir SelectionBackground plus bas pour le
// detail. Empiler six formes de verre cote a cote irait de toute facon contre
// les recommandations Apple, et l'etat selectionne a besoin d'une valeur qui ne
// depende pas du fond.

struct GlassSegmentedRow<Item: Identifiable & Equatable>: View {

    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                pill(for: item)
            }
        }
    }

    @ViewBuilder
    private func pill(for item: Item) -> some View {
        let isSelected = item == selection

        Button {
            withAnimation(Theme.Motion.morph) { selection = item }
        } label: {
            Text(title(item))
                .font(Theme.Typography.body(10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.Palette.ink : Theme.Palette.mist)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                // Le verre s'applique AU CONTENU, pas en `background` : un
                // materiau teinte a 0.92 est quasi opaque et recouvrirait le
                // libelle s'il etait composite par-dessus.
                .modifier(SelectionBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(item))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - SelectionBackground
//
// Fond de la pilule active : un aplat blanc, pas du verre.
//
// Liquid Glass adapte sa luminosite a ce qu'il recouvre — c'est sa raison
// d'etre. Pose sur le noir de l'encoche, un verre teinte blanc reste sombre :
// la pilule selectionnee devenait indistinguable des autres. Un etat de
// selection doit se lire quel que soit le fond, il lui faut donc une valeur
// propre.
//
// Le verre reste employe la ou il tient sa promesse : les boutons d'onglet, qui
// passent par `.glassProminent` et gerent eux-memes leur contraste.

private struct SelectionBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.background {
            Capsule().fill(
                isSelected ? Color.white : Theme.Palette.slate.opacity(0.7)
            )
        }
    }
}
