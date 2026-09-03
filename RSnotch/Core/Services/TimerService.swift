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

// MARK: - TimerMode
enum TimerMode: Sendable {
    case simple
    case pomodoro
}

// MARK: - PomodoroPhase
/// Phase du cycle Pomodoro. `.work` alterne avec une pause, longue toutes
/// les `sessionsBeforeLongBreak` sessions de travail (reglable par
/// l'utilisateur).
enum PomodoroPhase: Sendable, Equatable {
    case work
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .work: "Travail"
        case .shortBreak: "Pause courte"
        case .longBreak: "Pause longue"
        }
    }
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

    // MARK: Pomodoro
    //
    // Pas de second service : le cycle Pomodoro est un mode qui pilote
    // `selectedDuration`/`start()` par-dessus la machine a etats existante.
    // `state` (idle/running/paused/finished) continue de gouverner le
    // decompte quel que soit le mode ; seul l'enchainement automatique en
    // fin de phase est propre au Pomodoro (§ advancePomodoroPhase).

    private(set) var mode: TimerMode = .simple
    private(set) var pomodoroPhase: PomodoroPhase = .work
    private(set) var completedWorkSessions = 0

    /// Nombre de sessions de travail avant une pause longue. Reglable : les
    /// sources sur la technique s'accordent sur "toutes les 4 sessions" en
    /// standard, mais recommandent 2-3 pour des sessions plus longues que
    /// 25 min — pas de raison de figer ce que l'utilisateur regle lui-meme.
    var sessionsBeforeLongBreak = 4
    static let sessionsBeforeLongBreakRange = 2...6

    var pomodoroWorkMinutes = 25
    var pomodoroShortBreakMinutes = 5
    var pomodoroLongBreakMinutes = 15
    static let pomodoroWorkRange = 15...50
    static let pomodoroShortBreakRange = 3...15
    static let pomodoroLongBreakRange = 10...30

    // MARK: Interne

    private var endDate: Date?
    /// Sonnerie reelle, independante des notifications locales (cf. AlarmSound).
    private let alarm = AlarmSound()
    private var tickTask: Task<Void, Never>?
    private var hasRequestedAuthorization = false
    /// Route l'action « Reprendre maintenant » d'une notification de pause
    /// vers `skipBreak()`. Objet separe car `UNUserNotificationCenterDelegate`
    /// est un protocole Objective-C : il exige un `NSObject`, que `TimerService`
    /// n'est pas (et n'a pas besoin d'etre pour le reste de sa logique).
    private var notificationDelegate: TimerNotificationDelegate?

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

    /// Demarre un cycle Pomodoro depuis le debut (phase Travail, compteur de
    /// sessions remis a zero). Reutilise `start()` : le decompte lui-meme ne
    /// change pas de mecanisme, seul l'enchainement en fin de phase differe
    /// (§ refresh/advancePomodoroPhase).
    func startPomodoro() {
        mode = .pomodoro
        pomodoroPhase = .work
        completedWorkSessions = 0
        selectedDuration = .seconds(pomodoroWorkMinutes * 60)
        remaining = selectedDuration
        start()
    }

    /// Sort du cycle Pomodoro et revient au minuteur simple. Distinct de
    /// `stop()` : un simple arret laisserait `pomodoroPhase` en l'etat, et la
    /// prochaine reprise repartirait au milieu du cycle plutot que d'en
    /// sortir vraiment.
    func exitPomodoro() {
        mode = .simple
        stop()
    }

    /// Abrege la pause en cours et repart en Travail immediatement — pour
    /// l'utilisateur qui a fini sa pause plus tot. Sans effet hors pause.
    func skipBreak() {
        guard mode == .pomodoro, pomodoroPhase != .work else { return }
        silence()
        pomodoroPhase = .work
        selectedDuration = .seconds(pomodoroWorkMinutes * 60)
        remaining = selectedDuration
        endDate = Date().addingTimeInterval(selectedDuration.timeInterval)
        state = .running
        startTicking()
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

            if mode == .pomodoro {
                // Fin d'une session de travail : moment fort du cycle, merite
                // la sonnerie complete et le panneau qui s'ouvre — c'est le
                // signal qu'on attend vraiment. Fin d'une pause : nudge
                // discret pour reprendre, une sonnerie de 30 s a chaque
                // pause de 5 min serait plus nuisance que signal utile — les
                // sources sur l'UX d'un minuteur "qui se fond dans le fond"
                // vont dans ce sens.
                //
                // La phase qui vient de finir est capturee AVANT
                // `advancePomodoroPhase()` : celle-ci la change aussitot, et
                // `postNotification()` s'execute dans une Task detachee qui
                // ne tourne qu'apres — lire `pomodoroPhase` a ce moment-la
                // donnerait toujours la phase SUIVANTE, jamais celle qui
                // vient de sonner.
                let finishedPhase = pomodoroPhase
                if finishedPhase == .work {
                    ringFully()
                } else {
                    Task { await postNotification(finishedPhase: finishedPhase) }
                }
                advancePomodoroPhase()
            } else {
                ringFully()
                Task { await postNotification(finishedPhase: nil) }
            }
        } else {
            remaining = .seconds(left)
        }
    }

    private func ringFully() {
        alarm.start()
        isRinging = true
        onFinish?()
    }

    /// Passe a la phase suivante du cycle et relance immediatement le
    /// decompte — l'enchainement Pomodoro est automatique, contrairement au
    /// mode simple qui s'arrete a `finished`.
    private func advancePomodoroPhase() {
        switch pomodoroPhase {
        case .work:
            completedWorkSessions += 1
            pomodoroPhase = completedWorkSessions.isMultiple(of: sessionsBeforeLongBreak)
                ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            pomodoroPhase = .work
        }
        selectedDuration = .seconds(pomodoroPhaseMinutes * 60)
        remaining = selectedDuration
        silence()
        endDate = Date().addingTimeInterval(selectedDuration.timeInterval)
        state = .running
        startTicking()
    }

    private var pomodoroPhaseMinutes: Int {
        switch pomodoroPhase {
        case .work: pomodoroWorkMinutes
        case .shortBreak: pomodoroShortBreakMinutes
        case .longBreak: pomodoroLongBreakMinutes
        }
    }

    // MARK: Notification locale
    //
    // L'autorisation est demandee au premier demarrage de minuteur, pas au
    // lancement de l'app : une invite surgissant sans rapport avec une action
    // de l'utilisateur est refusee par reflexe, et App Review le releve.
    //
    // Categorie avec action « Passer » : la pause qui vient de finir propose
    // de reprendre le travail sans repasser par le panneau — coherent avec
    // `skipBreak()`, et avec l'idee qu'un minuteur pense pour l'arriere-plan
    // ne doit pas exiger de rouvrir l'app pour une decision aussi simple.
    private static let skipBreakCategoryID = "pomodoro.breakFinished"
    private static let skipBreakActionID = "pomodoro.skipToWork"

    private func requestNotificationAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let skipAction = UNNotificationAction(
            identifier: Self.skipBreakActionID,
            title: "Reprendre maintenant",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.skipBreakCategoryID,
            actions: [skipAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        let delegate = TimerNotificationDelegate(
            skipActionID: Self.skipBreakActionID,
            onSkip: { [weak self] in self?.skipBreak() }
        )
        notificationDelegate = delegate
        center.delegate = delegate
    }

    /// `finishedPhase` est la phase qui vient de se terminer, capturee par
    /// l'appelant AVANT `advancePomodoroPhase()` (§ refresh) — `nil` en mode
    /// simple, ou cette methode n'a pas de notion de phase.
    private func postNotification(finishedPhase: PomodoroPhase?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        // Autorisation refusee : le panneau affiche quand meme sa notification
        // compacte, l'utilisateur n'est pas laisse sans retour.
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        if let finishedPhase {
            content.title = "\(finishedPhase.label) terminée"
            if finishedPhase == .work {
                content.body = "Place à une pause."
            } else {
                content.body = "Pause finie, prêt à reprendre ?"
                content.categoryIdentifier = Self.skipBreakCategoryID
            }
        } else {
            content.title = "Minuteur terminé"
            content.body = "\(selectedMinutes) min écoulées."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

// MARK: - TimerNotificationDelegate
/// Recoit la reponse a l'action « Reprendre maintenant » de la notification
/// de fin de pause, et la relaie a `TimerService.skipBreak()`. `NSObject` est
/// requis par `UNUserNotificationCenterDelegate` (protocole Objective-C) ;
/// `@unchecked Sendable` car le seul etat mutable, `onSkip`, n'est jamais
/// modifie apres l'init — seulement appele, et toujours sur le MainActor
/// (§ onSkip capture `[weak self]` sur un `TimerService` MainActor-isole).
private final class TimerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let skipActionID: String
    private let onSkip: @MainActor () -> Void

    init(skipActionID: String, onSkip: @escaping @MainActor () -> Void) {
        self.skipActionID = skipActionID
        self.onSkip = onSkip
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == skipActionID else { return }
        await onSkip()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
