import AppKit
import SwiftUI

// MARK: - CompactIslandView
//
// Notification breve affichee dans le notch elargi. Le contenu ne passe JAMAIS
// derriere l'encoche physique : une reserve centrale de la largeur exacte du
// notch separe les deux colonnes. Sans elle, un titre un peu long disparait
// litteralement dans la dalle.

struct CompactIslandView: View {
    let payload: CompactIslandPayload
    /// Largeur de l'encoche a neutraliser au centre.
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Label {
                Text(payload.title)
                    .font(Theme.Typography.body(11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: payload.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        payload.emphasis == .alert ? Theme.Palette.signal : Theme.Palette.ember
                    )
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.trailing, 8)

            // Reserve du notch physique.
            Color.clear.frame(width: notchWidth)

            Group {
                if let detail = payload.detail {
                    Text(detail)
                        .font(Theme.Typography.data(11))
                        .foregroundStyle(Theme.Palette.mist)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.leading, 8)
        }
        .foregroundStyle(Theme.Palette.frost)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([payload.title, payload.detail].compactMap(\.self).joined(separator: ". "))
    }
}

// MARK: - IslandMetrics
//
// Largeur de l'annonce, MESUREE sur son texte.
//
// Une largeur fixe convient tant que les libelles sont courts, puis tronque
// sans prevenir : « Batterie faible » devenait « Batterie f… ». Les titres
// viennent de noms d'appareils et de morceaux, dont on ne maitrise pas la
// longueur — la mesure est le seul choix tenable.

enum IslandMetrics {
    static let horizontalPadding: CGFloat = 12
    static let gap: CGFloat = 8
    /// Icone + son espacement au titre.
    static let iconWidth: CGFloat = 22
    /// Plancher : en deca, l'annonce ne se distingue plus de l'encoche au repos.
    static let minimumContentWidth: CGFloat = 210

    /// Largeur des DEUX colonnes reunies, hors reserve d'encoche.
    ///
    /// Les colonnes encadrent la reserve centrale et se partagent l'espace a
    /// PARTS EGALES : la reserve doit rester pile sur l'encoche physique. Il
    /// faut donc dimensionner sur la plus large des deux, pas sur leur somme —
    /// sinon un detail court laisse le titre tronque alors que la place existe,
    /// de l'autre cote.
    static func contentWidth(for payload: CompactIslandPayload) -> CGFloat {
        // Jauge : la colonne droite ne porte pas du texte mais une regle de
        // largeur fixe. La mesurer comme du texte la tronquerait.
        if payload.level != nil {
            let leading = iconWidth + measure(
                payload.title, font: .systemFont(ofSize: 11, weight: .semibold)
            ) + horizontalPadding + gap
            let trailing = LevelIslandMetrics.trailingWidth(
                showsValue: payload.level?.showsValue == true
            ) + horizontalPadding + gap
            return max(minimumContentWidth, (max(leading, trailing) * 2).rounded(.up))
        }

        let title = measure(
            payload.title,
            font: .systemFont(ofSize: 11, weight: .semibold)
        )
        let detail = payload.detail.map {
            measure($0, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        } ?? 0

        let leading = iconWidth + title + horizontalPadding + gap
        let trailing = detail + horizontalPadding + gap
        let column = max(leading, trailing)
        return max(minimumContentWidth, (column * 2).rounded(.up))
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
