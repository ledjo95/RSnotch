import AppKit
import OSLog

private let alarmLog = Logger(subsystem: "com.varicube.RSnotch", category: "alarm")

// MARK: - AlarmSound
//
// Sonnerie de fin de minuteur.
//
// Une notification locale ne suffit pas : son son est joue une fois, il est
// coupe par le mode Concentration et l'utilisateur peut avoir refuse les
// notifications. Un minuteur qui ne sonne pas ne remplit pas son office, donc
// la sonnerie est jouee par l'app elle-meme, independamment de
// UNUserNotificationCenter.
//
// `NSSound` lit les sons systeme de /System/Library/Sounds. Ce repertoire est
// accessible en lecture depuis le bac a sable sans aucun entitlement : ce sont
// des ressources systeme, pas des fichiers utilisateur. Aucune capability
// supplementaire n'est donc requise pour App Review.

@MainActor
final class AlarmSound {

    /// Sons systeme candidats, par ordre de preference. Aucun n'est garanti :
    /// Apple retire des sons d'une version a l'autre, et un `NSSound(named:)`
    /// qui echoue rend `nil` sans lever d'erreur. On tente donc plusieurs noms
    /// avant d'abandonner, plutot que de laisser un minuteur muet.
    private static let candidates = ["Funk", "Glass", "Ping", "Submarine", "Tink"]

    /// Duree maximale de sonnerie. Une sonnerie en boucle que personne ne vient
    /// arreter — machine laissee seule, utilisateur parti — deviendrait une
    /// nuisance ; elle se tait donc d'elle-meme.
    private static let maximumDuration: Duration = .seconds(30)

    private var sound: NSSound?
    private var stopTask: Task<Void, Never>?

    private(set) var isRinging = false

    func start() {
        stop()

        guard let sound = Self.candidates.lazy.compactMap({ NSSound(named: $0) }).first else {
            alarmLog.notice("aucun son système disponible : sonnerie ignorée")
            return
        }

        sound.loops = true
        self.sound = sound
        isRinging = sound.play()
        alarmLog.notice("sonnerie démarrée : \(self.isRinging)")

        stopTask = Task { [maximumDuration = Self.maximumDuration] in
            try? await Task.sleep(for: maximumDuration)
            guard !Task.isCancelled else { return }
            self.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        guard let sound else { return }
        sound.stop()
        self.sound = nil
        isRinging = false
    }
}
