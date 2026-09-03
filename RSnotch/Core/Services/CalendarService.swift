import EventKit
import Foundation
import Observation

// MARK: - CalendarEventSnapshot
/// Ce dont l'onglet Agenda a besoin, et rien de plus.
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

// MARK: - CalendarService
/// Evenements lus depuis les calendriers deja configures dans Reglages
/// Systeme -> Internet Accounts (iCloud compris). EventKit est l'unique API,
/// publique, contrairement a la luminosite (§3) — aucune abstraction de
/// source n'est donc necessaire ici.
@MainActor
@Observable
final class CalendarService {

    private let store = EKEventStore()

    /// Etat d'autorisation courant, expose pour que l'onglet Agenda affiche
    /// directement son propre message d'accès refuse.
    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Evenements sur une plage arbitraire, tries par debut. Utilise par
    /// l'onglet Agenda pour peupler un mois entier — EventKit limite chaque
    /// requete a quatre ans, largement suffisant pour une grille mensuelle.
    /// N'attend pas l'autorisation : appele uniquement une fois `.fullAccess`
    /// deja confirme (§ CalendarTabView, qui affiche son propre etat refuse).
    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
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
    }

    /// `requestFullAccessToEvents` declenche le dialogue TCC au premier appel.
    /// Appele depuis `CalendarTabView.onAppear` uniquement (jamais au demarrage
    /// de l'app) : demander la permission avant que l'utilisateur ait ouvert
    /// l'onglet Agenda le surprendrait sans contexte.
    ///
    /// Sous Hardened Runtime, l'entitlement
    /// `com.apple.security.personal-information.calendars` (RSnotch.entitlements)
    /// est requis pour que tccd accepte meme d'AFFICHER ce dialogue — sans lui,
    /// `requestFullAccessToEvents` renvoie silencieusement `false`.
    func requestAccessIfNeeded() async {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        _ = try? await store.requestFullAccessToEvents()
    }
}
