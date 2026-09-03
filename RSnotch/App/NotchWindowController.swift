import AppKit
import SwiftData
import SwiftUI

// MARK: - NotchWindowController
//
// Assemble le trio panneau / modele / vue SwiftUI, et maintient la fenetre en
// phase avec l'ecran : changement de resolution, branchement d'un ecran
// externe, fermeture du capot.

@MainActor
final class NotchWindowController {

    /// Hauteur de la bande couverte par la fenetre. Fixe et genereuse : elle
    /// doit contenir le plus grand panneau possible sans jamais etre redimensionnee.
    private static let hostBandHeight: CGFloat = 260

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private(set) var model: NotchViewModel?

    // Modeles de fonctionnalites, crees une fois et partages par le panneau.
    // `widgets` est expose (pas `private`) : la fenetre de reglages doit
    // porter la MEME instance (§ SettingsWindowController.show), sinon
    // profils et disposition se desynchronisent des que les deux fenetres
    // sont ouvertes a la fois.
    let widgets = WidgetsViewModel()
    private let launcher = LaunchItemsViewModel()
    private let weather = WeatherService()
    private let calendar = CalendarService()
    private let countdown = TimerService()
    private let nowPlaying = NowPlayingViewModel()
    private let power = PowerService()
    private let bluetooth = BluetoothService()
    private let audio = SystemAudioService()
    private let brightness = DisplayBrightnessService()
    private let mediaKeys = MediaKeyInterceptor.shared
    private let spaces = SpaceHeuristicService()
    private var island: CompactIslandCoordinator?
    private let pocket = PocketStorageService()
    private let clipboard = ClipboardService(
        context: ModelContext(ClipboardStore.container),
        historyLimit: AppSettings.shared.clipboardLimit
    )

    private var screenObserver: (any NSObjectProtocol)?
    private var mouseMonitor: Any?

    // MARK: Cycle de vie

    func start() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry.measure(screen)

        let model = NotchViewModel(geometry: geometry)
        self.model = model

        let hosting = NotchHostingView(
            rootView: NotchRootView(
                model: model,
                widgets: widgets,
                launcher: launcher,
                countdown: countdown,
                nowPlaying: nowPlaying,
                spaces: spaces,
                pocket: pocket,
                weather: weather,
                calendar: calendar
            )
        )
        hosting.isPointInteractive = { [weak model] point in
            model?.acceptsPoint(point) ?? false
        }
        self.hostingView = hosting

        let frame = geometry.hostFrame(maxPanelHeight: Self.hostBandHeight)
        let panel = NotchPanel(contentRect: frame)
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        observeScreenChanges()
        model.isPointerInsidePanel = { [weak panel, weak model] in
            guard let panel, let model else { return false }
            return model.acceptsPoint(panel.convertPoint(fromScreen: NSEvent.mouseLocation))
        }

        observePointerExit()
        weather.start()
        nowPlaying.start()
        clipboard.start()
        pocket.load(emptyOnLaunch: AppSettings.shared.emptyPocketOnLaunch)
        // Le sas de reception ne doit rien conserver d'une session a l'autre.
        DropInbox.empty()
        observeSettings()
        observePanelState()
        applyPowerState()

        // Toutes les annonces passent par le coordinateur : lui seul decide de
        // ce qui merite d'interrompre, et a quelle cadence.
        let island = CompactIslandCoordinator { [weak model] payload in
            model?.present(payload)
        }
        self.island = island

        // Fin du decompte : le panneau le signale lui-meme, en plus de la
        // notification systeme. L'utilisateur qui a refuse les notifications
        // garde ainsi un retour visible.
        //
        // Pas d'island ici : `present(_:)` l'ignore quand le panneau est
        // ouvert, et il l'est justement puisqu'on vient de l'ouvrir.
        //
        // La sonnerie retentit (AlarmSound) : le panneau doit montrer d'ou elle
        // vient et offrir de quoi la couper. Il s'ouvre donc sur la carte du
        // minuteur — sur la page principale si elle y figure, sinon sur
        // l'onglet dedie. Une island de 4 secondes ne suffirait pas : elle se
        // retracterait pendant que l'alarme sonne encore.
        countdown.onFinish = { [weak model, weak self] in
            guard let model else { return }
            guard let self else { return }
            let showsTimerCard = self.widgets.widgets.contains { $0.kind == .timer }
            model.selectedTab = showsTimerCard ? .home : .timer
            model.expand()
            // Sans repli programme, le panneau resterait ouvert indefiniment :
            // le pointeur est ailleurs, aucun evenement de sortie ne viendra.
            // Le delai couvre la duree maximale de sonnerie ; passer la souris
            // sur le panneau l'annule, comme n'importe quel maintien.
            model.holdOpen(for: .seconds(30))
        }
        power.onEvent = { island.handle($0) }
        // Jauges systeme : elles remontent au coordinateur comme les autres
        // sources, mais par un chemin qui ignore la regle d'espacement — une
        // rampe de volume ne doit pas etre hachee.
        audio.onChange = { value, muted in
            guard AppSettings.shared.volumeHUDEnabled else { return }
            island.handleVolume(value, isMuted: muted)
        }
        brightness.onChange = { value in
            guard AppSettings.shared.brightnessHUDEnabled else { return }
            island.handleBrightness(value)
        }
        bluetooth.onEvent = { island.handle($0) }
        nowPlaying.onTrackChange = { island.handleTrackChange($0) }

        power.start()
        spaces.start()
        audio.start()
        brightness.start()
        startMediaKeyInterception()

        // L'enumeration Bluetooth declenche un dialogue TCC au premier appel,
        // et ce dialogue BLOQUE l'appel jusqu'a la reponse de l'utilisateur.
        // Sur le chemin de demarrage, il gelait tout ce qui suit : la fenetre
        // etait posee mais l'app restait muette tant que personne ne repondait.
        // Repousse apres l'initialisation, l'attente ne coute plus rien.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.isPanelActive else { return }
            #if DEBUG
            // Chaque reconstruction change la signature ad-hoc du binaire :
            // TCC ne reconnait plus l'app et repose sa question. Le dialogue
            // est modal et bloque les clics sur le panneau, ce qui empeche
            // d'eprouver le reste. RSNOTCH_DEBUG_NO_BLUETOOTH=1 le contourne.
            guard ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_NO_BLUETOOTH"] != "1"
            else { return }
            #endif
            self.bluetooth.start()
        }

        // Etat des reglages applique une fois tout en place : l'encoche peut
        // etre coupee, l'ouverture au survol desactivee, l'ecran impose.
        applySettings()
        if AppSettings.shared.panelEnabled, AppSettings.shared.expandOnLaunch {
            model.expand()
        }
    }

    func stop() {
        weather.stop()
        nowPlaying.stop()
        power.stop()
        bluetooth.stop()
        audio.stop()
        brightness.stop()
        mediaKeys.stop()
        spaces.stop()
        clipboard.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        model = nil
    }

    #if DEBUG
    /// Range quelques fichiers dans la Pocket, pour eprouver l'onglet sans
    /// avoir a piloter un glisser depuis le Finder.
    func seedDebugPocket() {
        let candidates = [
            "/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns",
            "/usr/share/dict/words",
            "/System/Library/Desktop Pictures/Solid Colors/Black.png"
        ].map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        // Passe par le sas, comme un vrai depot : c'est ce chemin-la qu'il faut
        // eprouver, pas une copie directe qui court-circuiterait le probleme.
        // Deux appels distincts = deux lots, dont un a fichier unique : c'est
        // exactement la distinction que l'UI doit rendre.
        let group = candidates.dropLast().compactMap(DropInbox.materialize)
        let single = candidates.suffix(1).compactMap(DropInbox.materialize)
        let added = pocket.add(group, movingSource: true) + pocket.add(single, movingSource: true)
        print("[debug] pocket seed: \(added) rangés en \(pocket.batches.count) lot(s), erreur=\(pocket.lastError ?? "aucune")")
    }

    /// Etat de lecture factice. `variant` : playing | paused | denied.
    func seedDebugMedia(_ variant: String) {
        let artwork = NSImage(
            contentsOfFile: "/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns"
        )
        switch variant {
        case "denied":
            nowPlaying.injectDebugState(.permissionDenied(app: .music))
        case "none":
            nowPlaying.injectDebugState(.noPlayerRunning)
        default:
            let track = NowPlayingTrack(
                title: "Sonnerie du filament",
                artist: "Atelier Varicube",
                album: "Encoche, vol. 2",
                duration: 227,
                isLoved: variant == "loved",
                artworkURL: nil
            )
            nowPlaying.injectDebugState(
                .ready(NowPlayingSnapshot(
                    app: .music,
                    state: variant == "paused" ? .paused : .playing,
                    track: track,
                    position: 84,
                    capturedAt: .now
                )),
                artwork: artwork
            )
        }
    }

    func startDebugTimer(seconds: Int) {
        countdown.startDebug(seconds: seconds)
    }

    /// Rejoue une annonce reelle, en passant par le coordinateur — donc par ses
    /// regles de cadence. Presenter directement un payload court-circuiterait
    /// justement ce qu'il faut eprouver.
    func fireDebugIsland(_ kind: String) {
        switch kind {
        case "battery":
            island?.handle(.low(percentage: 12, minutesRemaining: 34))
        case "plugged":
            island?.handle(.pluggedIn(78))
        case "bluetooth":
            island?.handle(.connected(BluetoothDevice(
                id: "debug", name: "AirPods de djo",
                isConnected: true, symbolName: "headphones"
            )))
        case "timer":
            island?.handleTimerFinished()
        case "spaces":
            spaces.runDebugScenario()
        case "volume":
            island?.handleVolume(0.42, isMuted: false)
        case "muted":
            island?.handleVolume(0.42, isMuted: true)
        case "brightness":
            island?.handleBrightness(0.68)
        case "btreal":
            // Passe par le service, pas par le coordinateur : c'est le maillon
            // qui n'a jamais ete eprouve.
            bluetooth.injectDebugConnection()
        default:
            break
        }
    }

    func forceDebugSpace(_ index: Int) {
        spaces.forceDebugIndex(index)
    }

    /// Eprouve le depot d'un dossier du Finder sur la grappe, sans avoir a
    /// piloter un vrai glisser.
    func seedDebugFolder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let ok = launcher.addDirectory(at: url)
        print("[debug] dossier « \(url.lastPathComponent) » : \(ok ? "ajouté" : "refusé"), " +
              "erreur=\(launcher.lastError ?? "aucune")")
    }

    /// Ajoute quelques applications systeme a la grappe, pour le developpement.
    func seedDebugApps() {
        guard launcher.items.isEmpty else { return }
        let candidates = [
            "/System/Applications/Safari.app",
            "/System/Applications/Utilities/Terminal.app",
            "/System/Applications/Music.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app"
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            launcher.addApp(at: url)
        }
        launcher.addFolder()
    }
    #endif

    /// Les reglages s'appliquent sans redemarrage : celui qui abaisse la limite
    /// d'historique, coupe l'encoche ou change d'ecran doit le voir tout de
    /// suite. `withObservationTracking` ne notifie qu'une fois — d'ou le
    /// reabonnement dans le `onChange`.
    // MARK: Cadence de repos (§ coût batterie)
    //
    // Panneau replie — l'etat 99 % du temps —, les sondages qui n'alimentent
    // que du contenu invisible n'ont pas besoin de leur cadence pleine. On les
    // RALENTIT, sans les suspendre : une copie faite panneau replie doit
    // toujours etre captee, une luminosite reglee au Centre de controle
    // toujours suivie, simplement avec un peu de retard que personne ne voit.
    // Reobserve a chaque changement d'etat, comme les reglages.

    private func observePanelState() {
        guard let model else { return }
        withObservationTracking {
            _ = model.state
        } onChange: {
            Task { @MainActor [weak self] in
                self?.applyPowerState()
                self?.observePanelState()
            }
        }
    }

    private func applyPowerState() {
        // `island` compte comme actif : une notification s'affiche, autant
        // garder les jauges reactives le temps qu'elle vit.
        let collapsed = model?.state == .collapsed
        clipboard.isLowPower = collapsed
        brightness.isLowPower = collapsed
    }

    private func observeSettings() {
        withObservationTracking {
            let settings = AppSettings.shared
            _ = settings.clipboardLimit
            _ = settings.panelEnabled
            _ = settings.openOnHover
            _ = settings.hoverDelayMilliseconds
            _ = settings.screenPreference
            _ = settings.showWithoutNotch
            _ = settings.simulatedBarWidth
            _ = settings.replaceSystemHUD
        } onChange: {
            Task { @MainActor [weak self] in
                self?.applySettings()
                self?.observeSettings()
            }
        }
    }

    /// Reporte l'etat des reglages sur les objets vivants.
    private func applySettings() {
        let settings = AppSettings.shared
        clipboard.historyLimit = settings.clipboardLimit
        model?.opensOnHover = settings.openOnHover
        model?.hoverOpenDelay = .milliseconds(settings.hoverDelayMilliseconds)
        setPanelActive(settings.panelEnabled)
        applyHUDInterception(settings.replaceSystemHUD)
        repositionForCurrentScreen()
    }

    // MARK: Encoche active (§3.9)
    //
    // Couper l'encoche ne se contente pas de masquer la fenetre : les services
    // qui l'alimentent s'arretent aussi. Continuer a interroger le
    // presse-papiers, les lecteurs et le Bluetooth pour une fenetre invisible
    // consommerait de la batterie sans rien afficher — et lirait des donnees
    // que l'utilisateur vient justement de demander de ne plus afficher.

    private var isPanelActive = true

    private func setPanelActive(_ active: Bool) {
        guard active != isPanelActive else { return }
        isPanelActive = active

        if active {
            panel?.orderFrontRegardless()
            weather.start()
            nowPlaying.start()
            clipboard.start()
            power.start()
            spaces.start()
            bluetooth.start()
            audio.start()
            brightness.start()
            startMediaKeyInterception()
        } else {
            model?.collapse()
            panel?.orderOut(nil)
            weather.stop()
            nowPlaying.stop()
            clipboard.stop()
            power.stop()
            spaces.stop()
            bluetooth.stop()
            audio.stop()
            brightness.stop()
            mediaKeys.stop()
        }
    }

    // MARK: Touches son / luminosite (§ jauges systeme)
    //
    // Le principe qui gouverne tout ce bloc : on n'avale une touche QUE si on
    // sait appliquer soi-meme le changement. Des que l'ecriture echoue —
    // sortie audio sans controle logiciel, symboles de luminosite absents —
    // l'evenement repart vers macOS, qui fera son travail et affichera son
    // HUD. Une touche morte serait bien pire qu'un HUD en double.

    private func startMediaKeyInterception() {
        guard AppSettings.shared.replaceSystemHUD else { return }

        mediaKeys.onKey = { [weak self] key, _ in
            guard let self else { return false }
            return self.handleMediaKey(key)
        }
        mediaKeys.start()
    }

    /// Bascule l'interception A CHAUD. Sans ce chemin, changer le reglage
    /// « Remplacer les jauges de macOS » ne prenait effet qu'au redemarrage
    /// suivant : l'interrupteur bougeait, le comportement non.
    private func applyHUDInterception(_ replace: Bool) {
        guard isPanelActive else { return }
        if replace {
            startMediaKeyInterception()
        } else {
            mediaKeys.stop()
        }
    }

    /// Rend `true` si RSnotch a traite la touche : elle est alors avalee.
    private func handleMediaKey(_ key: MediaKey) -> Bool {
        switch key {
        case .soundUp, .soundDown:
            guard AppSettings.shared.volumeHUDEnabled else { return false }
            let delta = key == .soundUp ? SystemAudioService.step : -SystemAudioService.step
            // Le volume est relu juste avant l'ecriture plutot que suivi de
            // notre cote : le Centre de controle ou une app ont pu le changer
            // depuis, et partir d'une valeur perimee ferait sauter la jauge.
            return audio.setVolume(audio.volume + delta)

        case .mute:
            guard AppSettings.shared.volumeHUDEnabled else { return false }
            return audio.toggleMute()

        case .brightnessUp, .brightnessDown:
            guard AppSettings.shared.brightnessHUDEnabled else { return false }
            let step = SystemAudioService.step
            let delta = key == .brightnessUp ? step : -step
            return brightness.setBrightness(brightness.brightness + delta)
        }
    }

    // MARK: Suivi de l'ecran

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionForCurrentScreen() }
        }
    }

    private func repositionForCurrentScreen() {
        guard let panel, let model else { return }

        // Aucun ecran ne convient : l'utilisateur a refuse la barre simulee et
        // aucun ecran a encoche n'est branche. On retire la fenetre plutot que
        // de la laisser sur un ecran qu'il n'a pas choisi.
        guard let screen = NotchGeometry.preferredScreen() else {
            panel.orderOut(nil)
            return
        }
        if isPanelActive, !panel.isVisible { panel.orderFrontRegardless() }

        let geometry = NotchGeometry.measure(screen)
        model.updateGeometry(geometry)
        panel.setFrame(
            geometry.hostFrame(maxPanelHeight: Self.hostBandHeight),
            display: true
        )
    }

    // MARK: Filet de securite du survol
    //
    // `onContinuousHover` couvre le cas nominal. Ce moniteur global rattrape le
    // cas ou le pointeur quitte la zone d'un mouvement rapide, entre deux
    // evaluations de tracking area, et laisserait le panneau ouvert.
    // Seuls les deplacements de souris sont observes — aucune saisie clavier,
    // aucune donnee lue : ce moniteur ne demande donc aucune autorisation.

    private func observePointerExit() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointerLocation() }
        }
    }

    private func evaluatePointerLocation() {
        guard let panel, let model, model.state.isExpanded, !model.isReceivingDrag else { return }
        let inWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        if !model.acceptsPoint(inWindow) {
            model.pointerExited()
        }
    }
}
