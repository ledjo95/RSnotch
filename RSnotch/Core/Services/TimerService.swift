import Foundation
import Observation
import UserNotifications

// MARK: - CountdownState
enum CountdownState: Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
}

// MARK: - TimerService
//
// Minuteur du panneau.
//
// Le decompte ne s'appuie PAS sur un compteur decremente a chaque tick : il
// derive le temps restant d'une date de fin. Un `Timer` qui perd des tops —
// mise en veille, charge systeme, panneau replie — ferait deriver l'affichage,
// et un minuteur qui ment sur la duree ecoulee n'a aucune valeur. Le tick ne
// sert qu'a rafraichir l'ecran.

@MainActor
@Observable
final class TimerService {

    // MARK: Etat

    private(set) var state: CountdownState = .idle
    /// Duree choisie par l'utilisateur.
    var selectedDuration: Duration = .seconds(5 * 60)
    /// Temps restant, recalcule a chaque tick.
    private(set) var remaining: Duration = .seconds(5 * 60)

    /// Appele quand le decompte atteint zero. Le panneau s'en sert pour
    /// s'ouvrir sur le minuteur et afficher une notification compacte.
    var onFinish: (@MainActor () -> Void)?

    /// Vrai tant que la sonnerie retentit. L'interface s'en sert pour proposer
    /// un bouton « couper » : une alarme qu'on ne peut pas faire taire depuis
    /// l'endroit ou on la voit est une alarme mal concue.
    private(set) var isRinging = false

    /// Presets proposes sous la regle.
    static let presets: [Int] = [5, 15, 25, 45]
    /// Bornes de la regle, en minutes.
    static let minimumMinutes = 1
    static let maximumMinutes = 120

    // MARK: Interne

    private var endDate: Date?
    /// Sonnerie reelle, independante des notifications locales (cf. AlarmSound).
    private let alarm = AlarmSound()
    private var tickTask: Task<Void, Never>?
    private var hasRequestedAuthorization = false

    // MARK: Commandes

    func start() {
        guard state != .running else { return }

        // Reprise de pause : on repart du temps restant, pas de la duree choisie.
        let interval = state == .paused
            ? remaining.timeInterval
            : selectedDuration.timeInterval
        guard interval > 0 else { return }

        silence()
        endDate = Date().addingTimeInterval(interval)
        state = .running
        startTicking()
        Task { await requestNotificationAuthorizationIfNeeded() }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        stopTicking()
    }

    func stop() {
        silence()
        state = .idle
        endDate = nil
        remaining = selectedDuration
        stopTicking()
    }

    /// Coupe la sonnerie sans toucher a l'etat du decompte. Separe de `stop()`
    /// pour que faire taire l'alarme ne remette pas silencieusement le minuteur
    /// a zero : ce sont deux intentions distinctes.
    func silence() {
        alarm.stop()
        isRinging = false
    }

    /// Ajuste la duree. Sans effet pendant un decompte : changer la cible en
    /// cours de route rendrait le temps affiche incoherent.
    func setDuration(minutes: Int) {
        guard state == .idle || state == .finished else { return }
        silence()
        let clamped = min(max(minutes, Self.minimumMinutes), Self.maximumMinutes)
        selectedDuration = .seconds(clamped * 60)
        remaining = selectedDuration
        if state == .finished { state = .idle }
    }

    /// Part de la duree encore a courir, entre 0 et 1. Sert au liseré de
    /// progression trace autour de la carte : un decompte se lit d'un coup
    /// d'oeil a la longueur du trait, sans avoir a decoder les chiffres.
    var progress: Double {
        let total = selectedDuration.timeInterval
        guard total > 0 else { return 0 }
        switch state {
        case .idle: return 1
        case .finished: return 0
        case .running, .paused: return min(max(remaining.timeInterval / total, 0), 1)
        }
    }

    var selectedMinutes: Int {
        Int(selectedDuration.timeInterval.rounded()) / 60
    }

    #if DEBUG
    /// Demarre un decompte de quelques secondes, pour eprouver le chemin
    /// « fin de minuteur » sans attendre une minute ni passer par la regle.
    func startDebug(seconds: Int) {
        selectedDuration = .seconds(seconds)
        remaining = selectedDuration
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        state = .running
        startTicking()
    }
    #endif

    // MARK: Tick

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                guard self.state == .running else { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func refresh() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            remaining = .seconds(0)
            state = .finished
            stopTicking()
            self.endDate = nil
            alarm.start()
            isRinging = true
            onFinish?()
            Task { await postNotification() }
        } else {
            remaining = .seconds(left)
        }
    }

    // MARK: Notification locale
    //
    // L'autorisation est demandee au premier demarrage de minuteur, pas au
    // lancement de l'app : une invite surgissant sans rapport avec une action
    // de l'utilisateur est refusee par reflexe, et App Review le releve.

    private func requestNotificationAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    private func postNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        // Autorisation refusee : le panneau affiche quand meme sa notification
        // compacte, l'utilisateur n'est pas laisse sans retour.
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Minuteur terminé"
        content.body = "\(selectedMinutes) min écoulées."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

// MARK: - Formatage
extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }

    /// `m:ss` sous l'heure, `h:mm:ss` au-dela. Les secondes sont arrondies au
    /// superieur : un minuteur qui affiche 0:00 alors qu'il reste une fraction
    /// de seconde parait casse.
    var countdownLabel: String {
        let total = Int(timeInterval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
