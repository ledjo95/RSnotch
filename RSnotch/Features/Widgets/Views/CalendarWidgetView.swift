import SwiftUI

// MARK: - CalendarWidgetView
//
// Prochains evenements du jour, un par ligne : pastille de la couleur du
// calendrier, heure, titre. Meme grammaire que WeatherWidgetView — etats
// idle/loading/ready/unavailable, carte entierement cliquable vers
// Calendrier.app.

struct CalendarWidgetView: View {

    let availability: CalendarAvailability

    var body: some View {
        Button { AppLauncher.open(.calendar) } label: {
            content
        }
        .buttonStyle(.plain)
        .help("Ouvrir Calendrier")
    }

    private var content: some View {
        Group {
            switch availability {
            case .idle, .loading:
                placeholder
            case .ready(let events):
                events.isEmpty ? AnyView(emptyDay) : AnyView(list(events))
            case .unavailable(let reason):
                unavailable(reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .contentShape(Rectangle())
    }

    // MARK: Etats

    private func list(_ events: [CalendarEventSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events.prefix(4)) { event in
                row(event)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(
                    red: event.calendarColor.red,
                    green: event.calendarColor.green,
                    blue: event.calendarColor.blue
                ))
                .frame(width: 6, height: 6)

            Text(timeLabel(for: event))
                .font(Theme.Typography.body(11, weight: .semibold))
                .foregroundStyle(Theme.Palette.mist)
                .frame(width: 42, alignment: .leading)

            Text(event.title)
                .font(Theme.Typography.body(13))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private func timeLabel(for event: CalendarEventSnapshot) -> String {
        event.isAllDay ? "Jour" : event.startDate.formatted(.dateTime.hour().minute())
    }

    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
            Text("Aucun évènement aujourd'hui")
                .font(Theme.Typography.body(12))
                .foregroundStyle(Theme.Palette.mist)
        }
        .accessibilityElement(children: .combine)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(Theme.Palette.filament)
                    .frame(width: index == 0 ? 150 : 100, height: 12)
            }
        }
        .accessibilityLabel("Agenda en cours de chargement")
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
            Text(reason)
                .font(Theme.Typography.body(12))
                .foregroundStyle(Theme.Palette.mist)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
