import Foundation
import IOBluetooth
import Observation
import OSLog

private let btLog = Logger(subsystem: "com.varicube.RSnotch", category: "bluetooth")

// MARK: - BluetoothDevice
struct BluetoothDevice: Identifiable, Equatable, Sendable {
    /// L'adresse materielle est le seul identifiant stable : deux casques du
    /// meme modele portent le meme nom par defaut.
    let id: String
    let name: String
    let isConnected: Bool
    /// Symbole SF deduit de la classe d'appareil declaree par le peripherique.
    let symbolName: String
}

// MARK: - BluetoothService
//
// Peripheriques Bluetooth appaires, via `IOBluetooth` — framework PUBLIC.
//
// CE QUE CETTE API DONNE : la liste des appareils appaires, leur nom, leur
// classe et leur etat de connexion, plus des notifications de connexion et de
// deconnexion.
//
// CE QU'ELLE NE DONNE PAS : le NIVEAU DE BATTERIE. Aucun framework public ne
// l'expose sur macOS. Le pourcentage qu'affiche le menu Bluetooth du systeme
// vient de cles IORegistry non documentees ; les lire ferait de RSnotch une app
// a API privee, donc irrecevable sur le Mac App Store. CoreBluetooth n'aide pas
// davantage : le service Battery (0x180F) suppose un peripherique BLE auquel
// l'app se connecte elle-meme, ce qui n'est pas le cas d'un casque deja apparie
// au systeme.
//
// La Phase 8 annonce donc les CONNEXIONS et DECONNEXIONS, pas les niveaux de
// batterie des accessoires. Limitation documentee, pas contournee.

@MainActor
@Observable
final class BluetoothService {

    private(set) var devices: [BluetoothDevice] = []
    /// `false` quand l'enumeration ne rend jamais rien : machine sans Bluetooth,
    /// ou acces refuse. Sert a masquer la fonction plutot qu'a afficher une
    /// liste vide qui ressemble a une panne.
    private(set) var isAvailable = false

    var onEvent: ((BluetoothEvent) -> Void)?

    @ObservationIgnored private var observer: ConnectionObserver?
    @ObservationIgnored private var connectedIDs: Set<String> = []
    @ObservationIgnored private var hasBaseline = false

    // MARK: Cycle de vie

    func start() {
        guard observer == nil else { return }
        let observer = ConnectionObserver { [weak self] in
            self?.refresh()
        }
        self.observer = observer
        refresh()
    }

    func stop() {
        observer?.invalidate()
        observer = nil
    }

    // MARK: Releve

    func refresh() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            btLog.notice("énumération indisponible")
            isAvailable = false
            return
        }
        isAvailable = true

        devices = paired.compactMap { device -> BluetoothDevice? in
            // L'identifiant doit etre STABLE d'un releve a l'autre : c'est lui
            // qui distingue « toujours connecte » de « vient de se connecter ».
            // Un UUID tire a chaque passage — le repli precedent — faisait
            // paraitre le meme appareil neuf a chaque fois.
            guard let id = device.addressString ?? device.name else { return nil }
            return BluetoothDevice(
                id: id,
                name: device.name ?? id,
                isConnected: device.isConnected(),
                symbolName: Self.symbol(for: device)
            )
        }
        .sorted { lhs, rhs in
            lhs.isConnected == rhs.isConnected
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : lhs.isConnected
        }

        btLog.notice("appairés : \(self.devices.count), connectés : \(self.devices.filter(\.isConnected).count)")
        emitEvents()
    }

    #if DEBUG
    /// Simule l'arrivee d'un appareil en passant par `emitEvents`, donc par le
    /// meme chemin qu'une vraie connexion. Eprouver le maillon service →
    /// coordinateur → island demande sinon de brancher un casque a la main.
    func injectDebugConnection() {
        hasBaseline = true
        connectedIDs = []
        devices = [BluetoothDevice(
            id: "debug-casque",
            name: "Casque de test",
            isConnected: true,
            symbolName: "headphones"
        )]
        emitEvents()
    }
    #endif

    private func emitEvents() {
        let nowConnected = Set(devices.filter(\.isConnected).map(\.id))
        defer {
            connectedIDs = nowConnected
            hasBaseline = true
        }
        // Premier releve : on prend l'etat pour reference. Annoncer au lancement
        // tout ce qui est deja connecte serait du bruit, pas une nouvelle.
        guard hasBaseline else { return }

        let arrived = nowConnected.subtracting(connectedIDs)
        let left = connectedIDs.subtracting(nowConnected)
        btLog.notice("diff : +\(arrived.count) −\(left.count), abonné=\(self.onEvent != nil)")

        for id in arrived {
            guard let device = devices.first(where: { $0.id == id }) else { continue }
            onEvent?(.connected(device))
        }
        for id in left {
            guard let device = devices.first(where: { $0.id == id }) else { continue }
            onEvent?(.disconnected(device))
        }
    }

    /// La classe d'appareil est publique et suffit a choisir une icone juste.
    private static func symbol(for device: IOBluetoothDevice) -> String {
        switch device.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio):
            return device.deviceClassMinor == UInt32(kBluetoothDeviceClassMinorAudioHeadphones)
                ? "headphones"
                : "hifispeaker.fill"
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            return "keyboard.fill"
        case UInt32(kBluetoothDeviceClassMajorPhone):
            return "iphone"
        case UInt32(kBluetoothDeviceClassMajorComputer):
            return "laptopcomputer"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - BluetoothEvent
enum BluetoothEvent: Equatable, Sendable {
    case connected(BluetoothDevice)
    case disconnected(BluetoothDevice)
}

// MARK: - ConnectionObserver
//
// `IOBluetooth` s'abonne par selecteur Objective-C : il lui faut un NSObject.
// Ce relais evite d'imposer l'heritage NSObject au service lui-meme, qui reste
// un `@Observable` Swift ordinaire.
//
// ATTENTION — LE FIL D'APPEL : ces rappels arrivent sur la file interne
// `com.apple.bluetooth.iobluetooth.coordinatorQueue`, PAS sur le fil principal.
// Marquer cette classe `@MainActor` faisait echouer le controle d'isolation de
// Swift 6 des qu'un appareil se connectait : `dispatch_assert_queue_fail`, donc
// SIGTRAP, donc arret immediat de l'app. La classe reste donc non isolee et
// saute explicitement sur l'acteur principal.
//
// `@unchecked Sendable` : `connectNotification` n'est touche que depuis
// l'acteur principal (creation, `invalidate()`). `disconnectNotifications`,
// lui, est ecrit depuis LA FILE IOBLUETOOTH (les callbacks Objective-C
// arrivent la, pas sur MainActor — voir plus haut) et peut etre lu/vide depuis
// MainActor par `invalidate()` : un verrou le protege contre ce croisement.

private final class ConnectionObserver: NSObject, @unchecked Sendable {

    private let handler: @MainActor @Sendable () -> Void
    private var connectNotification: IOBluetoothUserNotification?
    /// Jetons de deconnexion, un par appareil actuellement suivi. Proteges par
    /// `disconnectLock` : ecrits depuis la file IOBluetooth, purges depuis
    /// MainActor par `invalidate()`.
    ///
    /// `register(forDisconnectNotification:selector:)` rend un objet que
    /// L'APPELANT DOIT RETENIR : sans reference, ARC peut le liberer aussitot
    /// et desinscrire la notification avant qu'aucune deconnexion ne survienne
    /// — silencieusement, sans erreur. C'etait le cas ici : le jeton etait
    /// jete, ce qui expliquait qu'aucune deconnexion reelle n'ait jamais ete
    /// observee alors que les connexions, elles, fonctionnaient (leur jeton a
    /// elles, `connectNotification`, est bien stocke en propriete).
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private let disconnectLock = NSLock()

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func invalidate() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectLock.withLock {
            disconnectNotifications.values.forEach { $0.unregister() }
            disconnectNotifications.removeAll()
        }
    }

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        // La deconnexion s'ecoute appareil par appareil : on s'y abonne au
        // moment ou il se connecte, faute de notification globale. Le jeton
        // DOIT etre retenu (voir le commentaire sur `disconnectNotifications`).
        if let key = device.addressString ?? device.name {
            let token = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
            disconnectLock.withLock {
                disconnectNotifications[key]?.unregister()
                disconnectNotifications[key] = token
            }
        }
        notify()
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        notification.unregister()
        if let key = device.addressString ?? device.name {
            disconnectLock.withLock { _ = disconnectNotifications.removeValue(forKey: key) }
        }
        notify()
    }

    private func notify() {
        let handler = self.handler
        Task { @MainActor in handler() }
    }
}
