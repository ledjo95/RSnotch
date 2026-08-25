import Foundation
import IOKit.ps
import Observation

// MARK: - PowerSnapshot
struct PowerSnapshot: Equatable, Sendable {
    /// 0…100, ou `nil` sur une machine sans batterie (Mac de bureau).
    let percentage: Int?
    let isCharging: Bool
    let isPluggedIn: Bool
    /// Minutes restantes annoncees par le systeme, quand il sait les estimer.
    let minutesRemaining: Int?

    var hasBattery: Bool { percentage != nil }

    var symbolName: String {
        guard let percentage else { return "bolt.fill" }
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<70: return "battery.50percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - PowerService
//
// Etat de l'alimentation, via `IOPowerSources`.
//
// API PUBLIQUE ET SANS ENTITLEMENT : `IOPSCopyPowerSourcesInfo` est lisible
// depuis le bac a sable sans rien demander a l'utilisateur. Aucune permission
// n'est donc requise pour cette partie de la Phase 8.
//
// La notification est poussee par le systeme (`IOPSNotificationCreateRunLoopSource`)
// plutot que relevee en boucle : le niveau de batterie ne change que de temps
// en temps, et un sondage periodique reveillerait le processus pour rien.

@MainActor
@Observable
final class PowerService {

    private(set) var snapshot: PowerSnapshot?

    /// Emis quand un evenement merite d'etre annonce (seuil franchi, secteur
    /// branche ou debranche). Jamais a chaque variation d'un pourcent.
    var onEvent: ((PowerEvent) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    /// Etat precedent, pour ne signaler que les TRANSITIONS.
    @ObservationIgnored private var lastPercentage: Int?
    @ObservationIgnored private var lastPluggedIn: Bool?

    /// Seuils d'alerte, du plus grave au plus benin.
    private let thresholds = [10, 20]

    // MARK: Cycle de vie

    func start() {
        guard runLoopSource == nil else { return }
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            // Le rappel arrive sur la run loop principale : l'isolation est
            // garantie, mais le compilateur ne peut pas le savoir depuis un
            // pointeur C.
            MainActor.assumeIsolated { service.refresh() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func stop() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        self.runLoopSource = nil
    }

    // MARK: Releve

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        var current: PowerSnapshot?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            var percentage: Int?
            if let capacity = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int,
               maximum > 0 {
                percentage = Int((Double(capacity) / Double(maximum) * 100).rounded())
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let isPluggedIn = state == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            // -1 signifie « en cours de calcul » : le montrer afficherait
            // « -1 min restantes ».
            let raw = description[kIOPSTimeToEmptyKey] as? Int
            let minutes = (raw ?? -1) > 0 ? raw : nil

            current = PowerSnapshot(
                percentage: percentage,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesRemaining: minutes
            )
            break
        }

        // Machine sans batterie : on garde un instantane vide plutot que `nil`,
        // pour distinguer « pas encore releve » de « pas de batterie ».
        let resolved = current ?? PowerSnapshot(
            percentage: nil, isCharging: false, isPluggedIn: true, minutesRemaining: nil
        )
        snapshot = resolved
        emitEvents(for: resolved)
    }

    // MARK: Evenements

    private func emitEvents(for snapshot: PowerSnapshot) {
        defer {
            lastPercentage = snapshot.percentage
            lastPluggedIn = snapshot.isPluggedIn
        }
        guard let percentage = snapshot.percentage else { return }

        // Premier releve : on prend l'etat pour reference sans rien annoncer.
        // Signaler « batterie faible » au lancement serait du bruit — c'est un
        // etat, pas un evenement.
        guard let previous = lastPercentage, let wasPluggedIn = lastPluggedIn else { return }

        if snapshot.isPluggedIn != wasPluggedIn {
            onEvent?(snapshot.isPluggedIn ? .pluggedIn(percentage) : .unplugged(percentage))
            return
        }

        // Seuil franchi VERS LE BAS uniquement, et une seule fois par passage.
        for threshold in thresholds where previous > threshold && percentage <= threshold {
            guard !snapshot.isPluggedIn else { break }
            onEvent?(.low(percentage: percentage, minutesRemaining: snapshot.minutesRemaining))
            return
        }
    }
}

// MARK: - PowerEvent
enum PowerEvent: Equatable, Sendable {
    case low(percentage: Int, minutesRemaining: Int?)
    case pluggedIn(Int)
    case unplugged(Int)
}
