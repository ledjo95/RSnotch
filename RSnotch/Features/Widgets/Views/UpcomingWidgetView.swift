import SwiftUI

// MARK: - UpcomingWidgetView
//
// Carte des widgets dont la source de donnees arrive dans une phase ulterieure
// (Musique en Phase 7, Minuteur en Phase 5). Elle occupe la bonne place, a la
// bonne taille, et dit ce qu'elle attend — un carre vide donnerait l'impression
// d'un widget casse.

struct UpcomingWidgetView: View {

    let kind: WidgetKind
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
            Spacer(minLength: 0)
            Text(kind.title)
                .font(Theme.Typography.body(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.frost)
            Text(note)
                .font(Theme.Typography.body(11))
                .foregroundStyle(Theme.Palette.mist)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
