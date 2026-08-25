import Foundation
import Observation
import OSLog

private let brightnessLog = Logger(subsystem: "com.varicube.RSnotch", category: "brightness")

// MARK: - DisplayBrightnessService
//
// Suivi de la luminosite de l'ecran interne.
//
// SIMPLIFIE LE 25 AOUT 2026. La version precedente lisait une LUMINANCE dans le
// registre IOKit (`IOMFBBrightnessLevel`) et la reconvertissait en course par
// une courbe a deux regimes calee sur seize mesures. Ca marchait a un cran
// pres, mais la reference haute variait avec la lumiere ambiante et aucun
// pourcentage fiable ne pouvait en etre tire.
//
// La sortie du Mac App Store a rendu `DisplayServices` accessible (voir
// `BrightnessControl`, ou tout le code prive est isole) : la luminosite s'y lit
// DIRECTEMENT en 0…1, exactement la valeur du curseur des Reglages Systeme. La
// reconstitution n'a plus lieu d'etre, et la jauge peut de nouveau afficher un
// chiffre.
//
// Le suivi reste un SONDAGE : `DisplayServices` ne publie aucune notification,
// et l'interception ne couvre que les touches — le curseur du Centre de
// controle, lui, doit aussi etre suivi. Une lecture est negligeable.

@MainActor
@Observable
final class DisplayBrightnessService {

    /// Luminosite courante, 0…1. Valeur exacte.
    private(set) var brightness: Double = 0
    private(set) var isAvailable = false

    var onChange: (@MainActor (Double) -> Void)?

    /// Cadence de sondage. Assez rapide pour suivre un glissement au Centre de
    /// controle sans peser.
    private static let interval: Duration = .milliseconds(150)
    /// Seuil de variation, en fraction de course. Sous ce seuil, on ne
    /// derange pas : la valeur peut osciller d'un iota sans intention.
    private static let threshold = 0.004

    private var pollTask: Task<Void, Never>?

    // MARK: Cycle de vie

    func start() {
        guard pollTask == nil else { return }
        guard let initial = BrightnessControl.brightness() else {
            isAvailable = false
            brightnessLog.notice("luminosité illisible : jauge désactivée")
            return
        }
        brightness = initial
        isAvailable = true
        brightnessLog.notice("démarré : \(Int(initial * 100)) %")

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self else { return }
                self.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Applique une luminosite absolue et met l'etat a jour sans attendre le
    /// prochain sondage. Rend `false` si l'ecriture est impossible — l'appelant
    /// doit alors laisser la touche au systeme.
    @discardableResult
    func setBrightness(_ value: Double) -> Bool {
        guard BrightnessControl.setBrightness(value) else { return false }
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        isAvailable = true
        onChange?(clamped)
        return true
    }

    private func poll() {
        guard let value = BrightnessControl.brightness() else { return }
        guard abs(value - brightness) > Self.threshold else { return }
        brightness = value
        onChange?(value)
    }
}
