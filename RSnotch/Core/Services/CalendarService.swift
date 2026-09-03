import EventKit
import Foundation
import Observation

// MARK: - CalendarEventSnapshot
/// Ce dont le widget a besoin, et rien de plus — comme `WeatherSnapshot`.
struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: CGColorWrapper
}

/// `CGColor` n'est pas `Sendable` avant macOS 26 sur toutes les configs ; on
/// l'enveloppe pour traverser l'acteur sans avertissement, comme un simple
/// triplet de composantes RVB.
struct CGColorWrapper: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

// MARK: - CalendarAvailability
enum CalendarAvailability: Equatable, Sendable {
    case idle
    case loading
    case ready([CalendarEventSnapshot])
    case unavailable(reason: String)
}

// MARK: - CalendarService
/// Prochains evenements du jour, lus depuis les calendriers deja configures
/// dans Reglages Systeme -> Internet Accounts (iCloud compris). EventKit est
/// l'unique API, publique, contrairement a la luminosite (§3) — aucune
/// abstraction de source n'est donc necessaire ici.
@MainActor
@Observable
final class CalendarService {

    private(set) var availability: CalendarAvailability = .idle

    private let store = EKEventStore()
    private var refreshTask: Task<Void, Never>?

    /// Les evenements ne changent pas seconde par seconde ; 5 minutes suffisent
    /// a rattraper un ajout ou une annulation sans sonder en continu.
    private let refreshInterval: Duration = .seconds(5 * 60)

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        if case .ready = availability {} else { availability = .loading }

        let granted = await requestAccessIfNeeded()
        guard granted else {
            availability = .unavailable(reason: "Accès au calendrier refusé.")
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            availability = .unavailable(reason: "Calendrier indisponible.")
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let color = event.calendar.cgColor.flatMap { $0.components } ?? [0.6, 0.6, 0.6, 1]
                return CalendarEventSnapshot(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Sans titre",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarColor: CGColorWrapper(
                        red: Double(color[0]), green: Double(color[1]), blue: Double(color[2])
                    )
                )
            }
        availability = .ready(events)
    }

    /// `requestFullAccessToEvents` declenche le dialogue TCC au premier appel.
    /// Comme le Bluetooth (§ NotchWindowController), ce dialogue bloque
    /// jusqu'a la reponse — appele uniquement depuis `refresh()`, jamais au
    /// demarrage direct, pour ne pas geler le reste de l'initialisation.
    private func requestAccessIfNeeded() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }
}
