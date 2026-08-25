import SwiftUI

// MARK: - DateWidgetView
//
// Jour de la semaine et mois sur une ligne, quantieme en tres grand dessous.
// Le rouge marque le jour de la semaine — c'est le seul repere temporel de la
// carte, et la regle de couleur du design system lui reserve `signal`.
//
//
// L'action passe par un Button et NON par `onTapGesture` : la carte parente
// porte un `.draggable`, dont le geste prend le pas sur une simple tape. Le
// widget paraissait alors inerte.
//
// `TimelineView(.everyMinute)` plutot qu'un Timer : la vue se redessine quand
// le systeme le juge utile, et rien ne tourne pendant que le panneau est replie.

struct DateWidgetView: View {

    var body: some View {
        TimelineView(.everyMinute) { context in
            Button { AppLauncher.open(.calendar) } label: {
                content(for: context.date)
            }
            .buttonStyle(.plain)
            .help("Ouvrir Calendrier")
        }
    }

    private func content(for date: Date) -> some View {
        // Capitales gravees contre grand chiffre arrondi : c'est le contraste
        // qui porte la carte. En 15 pt gras, le jour et le mois pesaient
        // presque autant que le quantieme et la hierarchie s'annulait.
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .engraved(10, color: Theme.Palette.signal)
                Text(date.formatted(.dateTime.month(.abbreviated)))
                    .engraved(10, color: Theme.Palette.mist)
            }

            Text(date.formatted(.dateTime.day()))
                .font(Theme.Typography.display(58, weight: .bold))
                .foregroundStyle(Theme.Palette.frost)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // La carte entiere est cliquable : elle ne porte aucun autre controle,
        // viser une zone precise n'aurait pas de sens.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityHint("Ouvre Calendrier")
    }
}
