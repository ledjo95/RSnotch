import Foundation
import OSLog

private let islandLog = Logger(subsystem: "com.varicube.RSnotch", category: "island")

// MARK: - CompactIslandCoordinator
//
// Traduit les evenements des services en annonces breves, et decide lesquelles
// meritent d'interrompre l'utilisateur.
//
// L'existence de cette couche n'est pas cosmetique : sans elle, chaque service
// appellerait `present(_:)` directement et l'encoche clignoterait a chaque
// changement de morceau, chaque branchement de cable, chaque reconnexion d'un
// casque qui sort de veille. Les regles de silence vivent ici, en un seul
// endroit ou on peut les lire.

@MainActor
final class CompactIslandCoordinator {

    private let present: (CompactIslandPayload) -> Void

    /// Horodatage de la derniere annonce, toutes sources confondues.
    private var lastPresentedAt: Date?
    /// Deux annonces collees se chevauchent a l'ecran : la seconde remplacerait
    /// la premiere avant qu'elle soit lue.
    private let minimumSpacing: Duration = .seconds(1.2)

    /// Un casque Bluetooth qui sort de veille emet parfois plusieurs
    /// connexions de suite. On ne reannonce pas le meme appareil coup sur coup.
    private var lastDeviceAnnouncement: [String: Date] = [:]
    private let deviceCooldown: Duration = .seconds(30)

    init(present: @escaping (CompactIslandPayload) -> Void) {
        self.present = present
    }

    // MARK: Sources

    func handle(_ event: PowerEvent) {
        switch event {
        case .low(let percentage, let minutes):
            let detail = minutes.map { "\(percentage) % · \($0) min" } ?? "\(percentage) %"
            emit(CompactIslandPayload(
                symbolName: percentage <= 10 ? "battery.0percent" : "battery.25percent",
                title: "Batterie faible",
                detail: detail,
                emphasis: .alert,
                duration: .seconds(4)
            ))
        case .pluggedIn(let percentage):
            emit(CompactIslandPayload(
                symbolName: "battery.100percent.bolt",
                title: "Sur secteur",
                detail: "\(percentage) %"
            ))
        case .unplugged(let percentage):
            emit(CompactIslandPayload(
                symbolName: "battery.50percent",
                title: "Sur batterie",
                detail: "\(percentage) %"
            ))
        }
    }

    func handle(_ event: BluetoothEvent) {
        let (device, title): (BluetoothDevice, String) = switch event {
        case .connected(let device): (device, "Connecté")
        case .disconnected(let device): (device, "Déconnecté")
        }

        if let last = lastDeviceAnnouncement[device.id],
           Date().timeIntervalSince(last) < deviceCooldown.seconds {
            islandLog.notice("bluetooth écarté : trêve appareil")
            return
        }
        lastDeviceAnnouncement[device.id] = Date()

        emit(CompactIslandPayload(
            symbolName: device.symbolName,
            title: device.name,
            detail: title
        ))
    }

    func handleTrackChange(_ snapshot: NowPlayingSnapshot) {
        guard let track = snapshot.track else { return }
        emit(CompactIslandPayload(
            symbolName: "music.note",
            title: track.title.isEmpty ? "Lecture en cours" : track.title,
            detail: track.artist.isEmpty ? snapshot.app.displayName : track.artist
        ))
    }

    func handleTimerFinished() {
        emit(CompactIslandPayload(
            symbolName: "timer",
            title: "Minuteur terminé",
            emphasis: .alert,
            duration: .seconds(4)
        ))
    }

    // MARK: Jauges (volume, luminosite)
    //
    // Ces annonces contournent la regle d'espacement, et c'est voulu : un appui
    // maintenu sur la touche de volume produit une dizaine de variations par
    // seconde. Les espacer ferait sauter la jauge d'un palier a l'autre, ou
    // pire, la ferait disparaitre en pleine rampe. Une jauge ne s'empile pas
    // avec la precedente : elle la REMPLACE, et son identifiant reste stable
    // pour que la vue anime la valeur au lieu de rejouer l'apparition.

    private static let volumeIslandID = UUID()
    private static let brightnessIslandID = UUID()

    func handleVolume(_ value: Double, isMuted: Bool) {
        let symbol: String = if isMuted {
            "speaker.slash.fill"
        } else if value <= 0.001 {
            "speaker.fill"
        } else if value < 0.34 {
            "speaker.wave.1.fill"
        } else if value < 0.67 {
            "speaker.wave.2.fill"
        } else {
            "speaker.wave.3.fill"
        }

        emitLevel(CompactIslandPayload(
            id: Self.volumeIslandID,
            symbolName: symbol,
            title: isMuted ? "Son coupé" : "Volume",
            level: .init(value: value, isMuted: isMuted),
            duration: .seconds(1.4)
        ))
    }

    func handleBrightness(_ value: Double) {
        emitLevel(CompactIslandPayload(
            id: Self.brightnessIslandID,
            symbolName: value < 0.34 ? "sun.min.fill" : "sun.max.fill",
            title: "Luminosité",
            // Le chiffre est de retour : depuis le passage a
            // `DisplayServices`, la luminosite se lit exactement, et non plus
            // par reconstitution. Il n'y a plus de precision inventee a cacher.
            level: .init(value: value),
            duration: .seconds(1.4)
        ))
    }

    private func emitLevel(_ payload: CompactIslandPayload) {
        // La jauge compte comme une annonce pour les AUTRES sources : une
        // notification de batterie ne doit pas s'inserer au milieu d'une rampe
        // de volume.
        lastPresentedAt = Date()
        present(payload)
    }

    // MARK: Cadence

    private func emit(_ payload: CompactIslandPayload) {
        let now = Date()
        if let last = lastPresentedAt, now.timeIntervalSince(last) < minimumSpacing.seconds {
            islandLog.notice("écarté : deux annonces trop rapprochées")
            return
        }
        islandLog.notice("annonce transmise")
        lastPresentedAt = now
        present(payload)
    }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
