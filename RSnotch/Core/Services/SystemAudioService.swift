import CoreAudio
import Foundation
import Observation
import OSLog

private let audioLog = Logger(subsystem: "com.varicube.RSnotch", category: "audio")

// MARK: - SystemAudioService
//
// Volume de sortie du systeme (§ HUD volume).
//
// CoreAudio est PUBLIC et fonctionne tel quel dans le bac a sable : lire le
// volume d'un peripherique de SORTIE ne demande aucun entitlement (seule
// l'entree — le micro — en exige un, et l'app n'y touche pas).
//
// Le service n'interroge rien en boucle : CoreAudio previent par callback des
// qu'une propriete change. Un sondage periodique raterait les variations
// rapides d'un appui maintenu sur la touche de volume, et couterait du reveil
// processeur le reste du temps.

@MainActor
@Observable
final class SystemAudioService {

    /// Volume courant, 0…1.
    private(set) var volume: Double = 0
    private(set) var isMuted = false
    private(set) var isAvailable = false

    /// Appele a chaque variation, apres coalescence.
    var onChange: (@MainActor (Double, Bool) -> Void)?

    private var listener: PropertyListener?

    // MARK: Cycle de vie

    func start() {
        guard listener == nil else { return }
        let listener = PropertyListener { [weak self] in
            Task { @MainActor in self?.refresh(notify: true) }
        }
        listener.attach()
        self.listener = listener
        refresh(notify: false)
        audioLog.notice("démarré : volume \(Int(self.volume * 100)) %, disponible=\(self.isAvailable)")
    }

    func stop() {
        listener?.detach()
        listener = nil
    }

    // MARK: Lecture

    private func refresh(notify: Bool) {
        guard let device = Self.defaultOutputDevice() else {
            isAvailable = false
            return
        }
        guard let value = Self.volume(of: device) else {
            // Certaines sorties n'exposent aucun controle logiciel (HDMI, dock
            // audio) : le systeme lui-meme n'affiche pas de HUD dans ce cas, et
            // inventer une valeur serait mentir.
            isAvailable = false
            return
        }

        let muted = Self.isMuted(device)
        let changed = abs(value - volume) > 0.0005 || muted != isMuted
        volume = value
        isMuted = muted
        isAvailable = true

        guard notify, changed else { return }
        onChange?(value, muted)
    }

    // MARK: CoreAudio

    nonisolated private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    /// Volume principal, ou moyenne des canaux quand le peripherique n'expose
    /// pas d'element principal — c'est le cas de la plupart des sorties USB.
    nonisolated private static func volume(of device: AudioDeviceID) -> Double? {
        if let main = scalar(device, element: kAudioObjectPropertyElementMain) { return main }
        let channels = [1, 2].compactMap { scalar(device, element: AudioObjectPropertyElement($0)) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Double(channels.count)
    }

    nonisolated private static func scalar(
        _ device: AudioDeviceID, element: AudioObjectPropertyElement
    ) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? Double(value) : nil
    }

    nonisolated private static func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value == 1
    }

    // MARK: Ecriture
    //
    // Depuis que RSnotch avale les touches de volume (voir MediaKeyInterceptor),
    // c'est LUI qui doit appliquer le changement : le systeme ne le fera plus.
    // CoreAudio expose l'ecriture par la meme propriete que la lecture, et cela
    // ne demande aucun privilege particulier.

    /// Pas d'un cran de touche. macOS en compte seize sur toute la course ;
    /// s'en ecarter donnerait une progression etrangere au reste du systeme.
    static let step = 1.0 / 16.0

    /// Applique un volume absolu, 0…1. Rend `false` si la sortie courante
    /// n'expose aucun controle logiciel (HDMI, certaines stations d'accueil) :
    /// l'appelant doit alors laisser la touche au systeme plutot que de
    /// l'avaler pour rien.
    @discardableResult
    func setVolume(_ value: Double) -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        let clamped = min(max(value, 0), 1)

        var wrote = false
        // L'element principal d'abord ; a defaut, chaque canal separement —
        // c'est le cas de la plupart des sorties USB, qui n'exposent pas
        // d'element principal.
        if Self.write(clamped, to: device, element: kAudioObjectPropertyElementMain) {
            wrote = true
        } else {
            for channel in [1, 2] where Self.write(
                clamped, to: device, element: AudioObjectPropertyElement(channel)
            ) {
                wrote = true
            }
        }

        // Monter le volume sur une sortie coupee doit la retablir, comme le
        // fait macOS : sans cela, la jauge grimpe en silence.
        if wrote, clamped > 0, isMuted { Self.writeMute(false, to: device) }
        if wrote { refresh(notify: true) }
        return wrote
    }

    /// Bascule la coupure. Rend `false` si la sortie n'expose pas de mute.
    @discardableResult
    func toggleMute() -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        guard Self.writeMute(!isMuted, to: device) else { return false }
        refresh(notify: true)
        return true
    }

    nonisolated private static func write(
        _ value: Double, to device: AudioDeviceID, element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }

        var scalar = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &scalar) == noErr
    }

    @discardableResult
    nonisolated private static func writeMute(_ muted: Bool, to device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    // MARK: - PropertyListener
    //
    // Les callbacks CoreAudio arrivent sur une file a NOUS, jamais sur le thread
    // principal. Marquer cette classe @MainActor ferait echouer l'assertion de
    // file au premier evenement — meme piege que les callbacks IOBluetooth en
    // Phase 8. Elle reste donc nonisolee et saute explicitement sur l'acteur
    // principal.

    private final class PropertyListener: @unchecked Sendable {

        private let handler: @Sendable () -> Void
        private let queue = DispatchQueue(label: "com.varicube.RSnotch.audio")

        /// Ecoute du CHANGEMENT de peripherique de sortie par defaut. Fixe pour
        /// toute la duree de vie du service : c'est ce qui declenche la
        /// migration vers le nouveau peripherique.
        private var deviceChangeBlock: AudioObjectPropertyListenerBlock?

        /// Ecoute du volume/mute du peripherique COURANT. Re-creee a chaque
        /// declenchement de `deviceChangeBlock` : sans cette migration, brancher
        /// un casque laissait les listeners sur l'ancien peripherique (le
        /// haut-parleur du Mac) et le HUD ne suivait plus les touches de
        /// volume — c'etait le bug que le commentaire d'`attach()` annonçait
        /// sans que le code le fasse.
        private var deviceValueBlock: AudioObjectPropertyListenerBlock?
        private var deviceObserved: [(AudioObjectID, AudioObjectPropertyAddress)] = []

        init(handler: @escaping @Sendable () -> Void) {
            self.handler = handler
        }

        func attach() {
            let deviceChangeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.reattachToCurrentDevice()
                self?.handler()
            }
            self.deviceChangeBlock = deviceChangeBlock

            var systemAddress = address(
                kAudioHardwarePropertyDefaultOutputDevice,
                scope: kAudioObjectPropertyScopeGlobal
            )
            guard AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &systemAddress)
            else { return }
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &systemAddress, queue, deviceChangeBlock
            )

            attachToCurrentDevice()
        }

        func detach() {
            if let deviceChangeBlock {
                var systemAddress = address(
                    kAudioHardwarePropertyDefaultOutputDevice,
                    scope: kAudioObjectPropertyScopeGlobal
                )
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &systemAddress, queue, deviceChangeBlock
                )
            }
            deviceChangeBlock = nil
            detachFromDevice()
        }

        /// Point d'entree de la migration : quitte l'ancien peripherique,
        /// rejoint le nouveau par defaut.
        private func reattachToCurrentDevice() {
            detachFromDevice()
            attachToCurrentDevice()
        }

        private func attachToCurrentDevice() {
            guard let device = SystemAudioService.defaultOutputDevice() else { return }
            let block: AudioObjectPropertyListenerBlock = { [handler] _, _ in handler() }
            deviceValueBlock = block

            for element in [kAudioObjectPropertyElementMain, 1, 2] {
                observe(device, address(
                    kAudioDevicePropertyVolumeScalar,
                    scope: kAudioDevicePropertyScopeOutput,
                    element: AudioObjectPropertyElement(element)
                ), block)
            }
            observe(device, address(
                kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput
            ), block)
        }

        private func detachFromDevice() {
            guard let block = deviceValueBlock else { return }
            for (object, addr) in deviceObserved {
                var address = addr
                AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
            }
            deviceObserved.removeAll()
            deviceValueBlock = nil
        }

        private func address(
            _ selector: AudioObjectPropertySelector,
            scope: AudioObjectPropertyScope,
            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
        ) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        }

        private func observe(
            _ object: AudioObjectID,
            _ addr: AudioObjectPropertyAddress,
            _ block: @escaping AudioObjectPropertyListenerBlock
        ) {
            var address = addr
            guard AudioObjectHasProperty(object, &address) else { return }
            let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
            guard status == noErr else { return }
            deviceObserved.append((object, addr))
        }
    }
}
