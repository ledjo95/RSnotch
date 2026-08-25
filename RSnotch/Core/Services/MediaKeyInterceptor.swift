import AppKit
import Foundation
import Observation
import OSLog

private let keyLog = Logger(subsystem: "com.varicube.RSnotch", category: "mediakeys")

// MARK: - MediaKey
/// Touches materielles interceptees. Les codes viennent de `ev_keymap.h`
/// (`NX_KEYTYPE_*`), stables depuis des annees.
enum MediaKey: Int32 {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

// MARK: - MediaKeyInterceptor
//
// Capture des touches de volume et de luminosite, AVANT que macOS ne les voie.
//
// C'EST LA RAISON D'ETRE DE LA SORTIE DU MAC APP STORE. Le HUD natif est
// dessine par OSDUIHelper, un service protege par SIP qu'on ne peut ni
// decharger ni faire taire (verifie : plist « restricted », SIP « enabled »).
// La seule prise consiste a intercepter la touche en amont et a NE PAS LA
// RELAYER : sans evenement, pas de HUD. Or `CGEvent.tapCreate` est refuse a
// tout processus du bac a sable. D'ou la bascule en Developer ID.
//
// CONTREPARTIE : puisque l'evenement est avale, c'est RSnotch qui doit
// appliquer le changement. Volume par CoreAudio (public), luminosite par
// `BrightnessControl` (prive, isole). Si l'un des deux ne peut pas ecrire, la
// touche correspondante est RELAYEE telle quelle : mieux vaut le HUD de macOS
// que des touches mortes. C'est la regle qui gouverne tout ce fichier.
//
// AUTORISATION : l'interception exige l'Accessibilite, accordee par
// l'utilisateur dans Reglages Systeme et revocable a tout moment. Sans elle,
// aucun tap n'est cree et l'app retombe sur son comportement d'origine —
// observer les changements et afficher sa jauge A COTE de celle du systeme.

@MainActor
@Observable
final class MediaKeyInterceptor {

    /// Instance unique.
    ///
    /// L'interception, l'affichage de l'etat d'autorisation dans les deux UI de
    /// reglages (fenetre et onglet du notch) et le bouton « Autoriser » doivent
    /// tous parler AU MEME objet. Avec une instance par vue — l'etat de depart —
    /// accorder l'Accessibilite depuis un bouton mettait a jour un interceptor
    /// qui ne possedait aucun tap, pendant que celui du controleur, seul a en
    /// tenir un, n'en savait rien : la permission etait donnee, le HUD systeme
    /// restait. Un seul objet supprime la question.
    static let shared = MediaKeyInterceptor()

    private init() {}

    /// Vrai quand le tap tourne et avale effectivement les touches.
    private(set) var isIntercepting = false
    /// Vrai quand l'autorisation Accessibilite est accordee.
    private(set) var isTrusted = false

    /// Rend `true` si la touche a ete traitee — donc si l'evenement doit etre
    /// avale. `false` la laisse filer vers macOS.
    var onKey: (@MainActor (MediaKey, _ isRepeat: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Boite partagee avec le callback C, qui s'execute hors de tout acteur.
    private var box: CallbackBox?
    /// Sondage qui attend l'octroi de l'Accessibilite pour armer le tap.
    private var trustWatch: Task<Void, Never>?

    // MARK: Autorisation

    @discardableResult
    func refreshTrust() -> Bool {
        isTrusted = AXIsProcessTrusted()
        return isTrusted
    }

    /// Demande l'autorisation. macOS affiche sa propre invite, qui renvoie vers
    /// Reglages Systeme ; l'app ne peut pas l'accorder elle-meme.
    func requestTrust() {
        // La cle est un global mutable cote C, que Swift 6 refuse de lire tel
        // quel. Son nom est stable et documente : on l'ecrit en clair plutot
        // que de contourner l'isolation.
        let options = ["AXTrustedCheckOptionPrompt": true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Cycle de vie

    func start() {
        guard tap == nil else { return }
        guard refreshTrust() else {
            keyLog.notice("accessibilité refusée : interception inactive, HUD système conservé")
            // macOS accorde l'Accessibilite A CHAUD, sans redemarrage. On
            // attend donc l'octroi plutot que d'abandonner : sans ce guet,
            // l'utilisateur autorisait la permission et le HUD systeme
            // continuait de s'afficher jusqu'au lancement suivant.
            watchForTrust()
            return
        }
        trustWatch?.cancel()
        trustWatch = nil

        let box = CallbackBox { [weak self] key, isRepeat in
            // Le callback arrive sur le run loop principal (le tap y est
            // attache), mais hors de l'isolation d'acteur : on y rentre
            // explicitement plutot que de supposer.
            MainActor.assumeIsolated {
                guard let self, let handler = self.onKey else { return false }
                return handler(key, isRepeat)
            }
        }
        self.box = box

        // `CGEventType` n'expose pas de cas pour NSSystemDefined : la valeur
        // brute 14 est celle de `NX_SYSDEFINED`, definie par IOKit.
        let systemDefinedType: UInt32 = 14
        let mask = CGEventMask(1 << systemDefinedType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // `.defaultTap` = actif : il peut avaler.
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // Le systeme desactive le tap s'il juge l'app trop lente. Il
                // faut le rearmer, sinon l'interception s'arrete en silence et
                // les touches cessent de repondre.
                guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
                    if let refcon {
                        let box = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue()
                        box.reenable()
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon,
                      let parsed = MediaKeyEvent(event: event)
                else { return Unmanaged.passUnretained(event) }

                let box = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue()
                // Seule la PRESSION est traitee ; le relachement est avale avec
                // elle, sinon macOS recevrait une moitie d'evenement.
                guard parsed.isDown else {
                    return box.swallowsRelease(parsed.key) ? nil : Unmanaged.passUnretained(event)
                }
                return box.handle(parsed) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else {
            keyLog.error("création du tap refusée malgré l'accessibilité accordée")
            self.box = nil
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        box.tap = tap
        self.tap = tap
        self.runLoopSource = source
        isIntercepting = true
        keyLog.notice("interception active : les touches son/luminosité ne vont plus au système")
    }

    func stop() {
        trustWatch?.cancel()
        trustWatch = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        box = nil
        isIntercepting = false
    }

    /// Sonde l'autorisation jusqu'a ce qu'elle arrive, puis arme le tap.
    ///
    /// Deux secondes de cadence : accorder l'Accessibilite passe par les
    /// Reglages Systeme, c'est une action de plusieurs secondes cote
    /// utilisateur — inutile de sonder plus vite. Le guet s'auto-annule des que
    /// le tap est arme (`start()` remet `trustWatch` a nil).
    private func watchForTrust() {
        guard trustWatch == nil else { return }
        trustWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if self.refreshTrust() {
                    keyLog.notice("accessibilité accordée à chaud : armement du tap")
                    self.start()
                    return
                }
            }
        }
    }
}

// MARK: - MediaKeyEvent
/// Decodage d'un evenement `NSSystemDefined`. Le code de touche et l'etat
/// tiennent dans `data1` : bits 16-31 le code, bit 8 l'etat relache.
private struct MediaKeyEvent {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool

    init?(event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype == .screenChanged  // sous-type 8 : touches auxiliaires
        else { return nil }

        let data = nsEvent.data1
        guard let key = MediaKey(rawValue: Int32((data & 0xFFFF_0000) >> 16)) else { return nil }
        self.key = key
        self.isDown = ((data & 0x0000_FF00) >> 8) == 0x0A
        self.isRepeat = (data & 0x1) == 1
    }
}

// MARK: - CallbackBox
//
// Passerelle entre le callback C du tap — qui ne capture rien et recoit un
// pointeur brut — et le service Swift isole sur l'acteur principal.

private final class CallbackBox {

    /// Rend `true` si la touche a ete traitee, donc si l'evenement doit etre avale.
    private let handler: (MediaKey, Bool) -> Bool
    /// Touches dont la pression a ete avalee : leur relachement doit l'etre
    /// aussi. Sans ce suivi, macOS recevrait un relachement orphelin et
    /// rallumerait son HUD.
    private var swallowed: Set<Int32> = []
    var tap: CFMachPort?

    init(handler: @escaping (MediaKey, Bool) -> Bool) {
        self.handler = handler
    }

    func handle(_ event: MediaKeyEvent) -> Bool {
        let taken = handler(event.key, event.isRepeat)
        if taken { swallowed.insert(event.key.rawValue) } else { swallowed.remove(event.key.rawValue) }
        return taken
    }

    func swallowsRelease(_ key: MediaKey) -> Bool {
        swallowed.remove(key.rawValue) != nil
    }

    func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        keyLog.notice("tap réarmé après désactivation par le système")
    }
}
