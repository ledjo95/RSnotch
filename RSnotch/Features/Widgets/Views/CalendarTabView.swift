import SwiftUI

// MARK: - CalendarTabView
//
// Grille mensuelle façon Calendrier.app : sept colonnes, un point sous les
// jours porteurs d'évènements, le jour sélectionné en surbrillance. La liste
// détaillée du jour sélectionné vit à droite — la largeur de l'onglet (§
// Theme.Metrics.contentWidth) le permet, et ça évite d'empiler grille et
// liste dans une hauteur déjà comptée (§ Theme.Metrics.contentHeight).
//
// Interroge `CalendarService` à la demande pour le mois affiché : naviguer
// d'un mois à l'autre déclenche directement une nouvelle requête EventKit,
// sans dépendre d'un quelconque cycle de rafraîchissement en tâche de fond.

struct CalendarTabView: View {

    let service: CalendarService

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    /// Reflet local de `service.isAuthorized` : ce dernier est un computed
    /// property adossé à `EKEventStore.authorizationStatus`, qui ne déclenche
    /// aucune notification d'observation SwiftUI de lui-même. Sans cet état,
    /// la vue resterait figée sur "accès refusé" même après que l'utilisateur
    /// ait accordé la permission dans le dialogue TCC.
    @State private var isAuthorized = false

    private var calendar: Calendar { .current }

    var body: some View {
        Group {
            if isAuthorized {
                content
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Ne demande le dialogue TCC que si l'onglet est reellement
            // ouvert — jamais au demarrage de l'app (§ CalendarService).
            await service.requestAccessIfNeeded()
            isAuthorized = service.isAuthorized
            reloadMonth()
        }
        .onChange(of: visibleMonth) { _, _ in reloadMonth() }
    }

    private var content: some View {
        HStack(spacing: Theme.Metrics.contentSpacing) {
            VStack(spacing: 8) {
                header
                weekdayRow
                grid
            }
            .frame(width: 420)

            dayDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: En-tête mois

    private var header: some View {
        HStack {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(Theme.Typography.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.frost)
                .textCase(.uppercase)

            Spacer(minLength: 8)

            Button("Aujourd’hui") {
                withAnimation(Theme.Motion.morph) {
                    let today = calendar.startOfDay(for: .now)
                    visibleMonth = today
                    selectedDay = today
                }
            }
            .buttonStyle(.plain)
            .font(Theme.Typography.body(10, weight: .medium))
            .foregroundStyle(Theme.Palette.mist)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.Palette.slate.opacity(0.7)))

            GlassRoundButton(symbolName: "chevron.left", label: "Mois précédent", side: 22) {
                withAnimation(Theme.Motion.morph) { shiftMonth(by: -1) }
            }
            GlassRoundButton(symbolName: "chevron.right", label: "Mois suivant", side: 22) {
                withAnimation(Theme.Motion.morph) { shiftMonth(by: 1) }
            }
        }
    }

    private func shiftMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = next
    }

    // MARK: Grille

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(Theme.Typography.body(9, weight: .medium))
                    .foregroundStyle(Theme.Palette.mist)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Lundi en premier, comme la capture de référence — `calendar.veryShortWeekdaySymbols`
    /// suit `firstWeekday` du calendrier courant, déjà correct pour un utilisateur fr_FR.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private var grid: some View {
        let weeks = monthGrid
        return VStack(spacing: 2) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 2) {
                    ForEach(weeks[weekIndex], id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date?) -> some View {
        Group {
            if let day {
                Button {
                    withAnimation(Theme.Motion.morph) { selectedDay = day }
                } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.day()))
                            .font(Theme.Typography.body(11, weight: isToday(day) ? .bold : .regular))
                            .foregroundStyle(dayTextColor(day))
                        Circle()
                            .fill(Theme.Palette.ember)
                            .frame(width: 3, height: 3)
                            .opacity(hasEvents(on: day) ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if calendar.isDate(day, inSameDayAs: selectedDay) {
                            Circle().fill(Theme.Palette.slate)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(maxWidth: .infinity).frame(height: 28)
            }
        }
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    private func dayTextColor(_ day: Date) -> Color {
        guard calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month) else {
            return Theme.Palette.mist.opacity(0.5)
        }
        return isToday(day) ? Theme.Palette.ember : Theme.Palette.frost
    }

    /// Semaines du mois affiché, complétées avec les jours des mois adjacents
    /// pour remplir des lignes pleines — `nil` marque une case sans jour
    /// quand la grille doit malgré tout garder 7 colonnes.
    private var monthGrid: [[Date?]] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        var days: [Date] = []
        var cursor = firstWeek.start
        while cursor < monthInterval.end || !calendar.isDate(cursor, equalTo: monthInterval.end, toGranularity: .day) {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            if days.count >= 42 { break }
        }
        // Complete jusqu'a la derniere semaine pleine du mois.
        while days.count % 7 != 0 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: days[days.count - 1]) else { break }
            days.append(next)
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private func hasEvents(on day: Date) -> Bool {
        !eventsCache[calendar.startOfDay(for: day), default: []].isEmpty
    }

    /// Chargé une fois par mois affiché plutôt qu'une requête EventKit par
    /// case de la grille — `events(from:to:)` couvre tout le mois visible
    /// (marges incluses) en un seul appel.
    @State private var eventsCache: [Date: [CalendarEventSnapshot]] = [:]

    private func reloadMonth() {
        let days = monthGrid.flatMap { $0.compactMap { $0 } }
        guard
            let firstDay = days.first,
            let lastDay = days.last,
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else { return }

        let events = service.events(from: firstDay, to: end)
        var grouped: [Date: [CalendarEventSnapshot]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            grouped[day, default: []].append(event)
        }
        eventsCache = grouped
    }

    // MARK: Détail du jour

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Theme.Typography.body(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.frost)

            let dayEvents = eventsCache[calendar.startOfDay(for: selectedDay)] ?? []
            if dayEvents.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.Palette.mist)
                    Text("Aucun évènement")
                        .font(Theme.Typography.body(12))
                        .foregroundStyle(Theme.Palette.mist)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dayEvents) { event in
                            eventRow(event)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func eventRow(_ event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(
                    red: event.calendarColor.red,
                    green: event.calendarColor.green,
                    blue: event.calendarColor.blue
                ))
                .frame(width: 6, height: 6)

            Text(event.isAllDay ? "Jour" : event.startDate.formatted(.dateTime.hour().minute()))
                .font(Theme.Typography.body(11, weight: .semibold))
                .foregroundStyle(Theme.Palette.mist)
                .frame(width: 48, alignment: .leading)

            Text(event.title)
                .font(Theme.Typography.body(13))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    // MARK: Etat refusé

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
            Text("Accès au calendrier refusé.")
                .font(Theme.Typography.body(12))
                .foregroundStyle(Theme.Palette.mist)
        }
    }
}
