import AppKit
import Foundation
import OSLog
import Observation

private let mediaLog = Logger(subsystem: "com.varicube.RSnotch", category: "media")

// MARK: - NowPlayingViewModel
//
// Etat de lecture expose a l'UI.
//
// Rythme d'interrogation : chaque releve est un aller-retour Apple Events, donc
// un reveil de Music.app. Interroger a la seconde pour animer une barre de
// progression serait du gaspillage pur — la position est donc EXTRAPOLEE cote
// vue depuis `capturedAt`, et le releve ne sert qu'a resynchroniser.
//
// Le vrai declencheur reste la notification distribuee publique du lecteur
// (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) :
// un changement de morceau se voit immediatement, sans polling serre.

@MainActor
@Observable
final class NowPlayingViewModel {

    private(set) var availability: MediaAvailability = .idle
    private(set) var artwork: NSImage?

    /// Position en cours de reglage par l'utilisateur. Tant qu'elle est non nulle,
    /// l'affichage la suit au lieu de suivre le lecteur : sans cela, le curseur
    /// sauterait en arriere a chaque releve pendant qu'on le tire.
    private(set) var scrubPosition: TimeInterval?

    /// Point d'accroche pour la Phase 8 (island « lecture en cours »).
    var onTrackChange: ((NowPlayingSnapshot) -> Void)?

    // Plomberie interne : rien ici ne pilote un rendu, donc rien ne doit
    // declencher d'invalidation de vue.
    @ObservationIgnored private let service = MusicScriptingService()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastSignature: String?
    @ObservationIgnored private var isRefreshing = false
    /// Lecteur retenu tant qu'il joue, pour ne pas osciller entre deux apps
    /// ouvertes en meme temps.
    @ObservationIgnored private var stickyApp: MediaApp?

    /// Resynchronisation. Assez espacee pour ne pas peser, assez frequente pour
    /// rattraper une avance prise par un seek fait ailleurs.
    private let playingInterval: Duration = .seconds(5)
    private let idleInterval: Duration = .seconds(15)

    // MARK: Cycle de vie

    func start() {
        guard pollTask == nil else { return }
        subscribeToPlayerNotifications()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.availability.snapshot?.state.isPlaying == true
                    ? self?.playingInterval : self?.idleInterval
                guard let interval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }

    /// Les notifications sont diffusees a tout le systeme et ne portent aucune
    /// donnee privee : les recevoir ne demande ni entitlement ni consentement.
    /// Seul le pilotage par Apple Events en demande un.
    private func subscribeToPlayerNotifications() {
        let center = DistributedNotificationCenter.default()
        for app in MediaApp.allCases {
            let token = center.addObserver(
                forName: app.playerInfoNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stickyApp = app
                    Task { await self?.refresh() }
                }
            }
            observers.append(token)
        }
    }

    // MARK: Releve

    func refresh() async {
        // La boucle d'interrogation et les notifications du lecteur peuvent
        // arriver ensemble. Sans ce verrou, deux releves s'entrelacent sur
        // leurs `await` et se disputent le chargement de la pochette.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let running = MusicScriptingService.runningPlayers()
        mediaLog.debug("lecteurs détectés : \(running.map(\.rawValue).joined(separator: ","), privacy: .public) / apps vues : \(NSWorkspace.shared.runningApplications.count)")
        guard !running.isEmpty else {
            stickyApp = nil
            lastSignature = nil
            artwork = nil
            availability = .noPlayerRunning
            return
        }

        // Le lecteur retenu garde la main tant qu'il tourne encore.
        let candidates: [MediaApp] = if let sticky = stickyApp, running.contains(sticky) {
            [sticky] + running.filter { $0 != sticky }
        } else {
            running
        }

        var fallback: MediaAvailability?
        for app in candidates {
            do {
                let snapshot = try await service.snapshot(for: app)
                // Le titre reste PRIVE : le marquer public inscrirait l'historique
                // d'ecoute de l'utilisateur en clair dans le journal unifie, lisible
                // par tout processus administrateur.
                mediaLog.debug("relevé \(app.rawValue, privacy: .public) : état=\(snapshot.state.rawValue, privacy: .public), piste \(snapshot.track == nil ? "absente" : "présente", privacy: .public)")
                // Un lecteur ouvert mais a l'arret ne doit pas empecher l'autre
                // d'etre consulte : on le garde de cote et on continue.
                guard snapshot.state != .stopped else {
                    fallback = fallback ?? .ready(snapshot)
                    continue
                }
                await apply(snapshot)
                return
            } catch AppleScriptError.notAuthorized {
                fallback = .permissionDenied(app: app)
            } catch AppleScriptError.targetNotRunning {
                continue
            } catch AppleScriptError.timedOut {
                // Lecteur lance mais muet. On passe au suivant plutot que de
                // laisser le widget vide a cause de lui.
                mediaLog.debug("\(app.rawValue, privacy: .public) ne répond pas")
                continue
            } catch {
                fallback = fallback ?? .failed("\(app.displayName) n'a pas répondu.")
            }
        }

        if case .ready(let snapshot)? = fallback {
            await apply(snapshot)
        } else {
            availability = fallback ?? .noPlayerRunning
        }
    }

    private func apply(_ snapshot: NowPlayingSnapshot) async {
        stickyApp = snapshot.app
        availability = .ready(snapshot)

        guard let track = snapshot.track else {
            lastSignature = nil
            artwork = nil
            return
        }
        guard track.signature != lastSignature else { return }

        let isFirstTrack = lastSignature == nil
        lastSignature = track.signature
        await loadArtwork(for: snapshot.app, track: track)

        // Pas d'annonce au tout premier releve : signaler un morceau qui jouait
        // deja avant le lancement de RSnotch serait du bruit, pas une nouvelle.
        if !isFirstTrack, snapshot.state.isPlaying {
            onTrackChange?(snapshot)
        }
    }

    private func loadArtwork(for app: MediaApp, track: NowPlayingTrack) async {
        artwork = nil
        switch app {
        case .music:
            artwork = try? await service.artwork(for: app)
        case .spotify:
            // Spotify ne publie sa pochette que par URL distante — d'ou
            // l'entitlement reseau. Un echec reste silencieux : le widget a
            // deja un repli visuel.
            guard let url = track.artworkURL else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            guard lastSignature == track.signature else { return }
            artwork = NSImage(data: data)
        }
    }

    // MARK: Commandes

    /// Toute commande est suivie d'un releve : le lecteur ne previent pas
    /// systematiquement d'un simple play/pause.
    private func command(_ body: @escaping @Sendable (MediaApp) async throws -> Void) {
        guard let app = availability.snapshot?.app else { return }
        Task {
            do {
                try await body(app)
            } catch AppleScriptError.notAuthorized {
                availability = .permissionDenied(app: app)
                return
            } catch {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            await refresh()
        }
    }

    func togglePlayPause() { command { try await MusicScriptingService().togglePlayPause($0) } }
    func nextTrack() { command { try await MusicScriptingService().nextTrack($0) } }
    func previousTrack() { command { try await MusicScriptingService().previousTrack($0) } }

    func toggleLoved() {
        guard let snapshot = availability.snapshot,
              let track = snapshot.track,
              snapshot.app.supportsLoving else { return }
        let target = !track.isLoved
        command { try await MusicScriptingService().setLoved(target, on: $0) }
    }

    /// Passe au lecteur. `NSWorkspace` suffit et n'ajoute aucun entitlement :
    /// l'equivalent AppleScript (`activate`) exigerait le groupe d'acces
    /// `user-interface`, que l'app ne demande pas.
    func openPlayer() {
        guard let app = availability.snapshot?.app,
              let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: app.bundleIdentifier
              ) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: Reglage de position

    func beginScrub(at position: TimeInterval) {
        scrubPosition = position
    }

    func updateScrub(to position: TimeInterval) {
        guard scrubPosition != nil else { return }
        scrubPosition = position
    }

    func endScrub() {
        guard let target = scrubPosition else { return }
        seek(to: target)
    }

    /// Deplace la lecture. `scrubPosition` reste EPINGLE jusqu'au releve qui
    /// suit : le lecteur met un instant a appliquer le saut, et relacher tout de
    /// suite ferait revenir la barre a l'ancienne position avant de repartir en
    /// avant — un aller-retour bien visible.
    func seek(to target: TimeInterval) {
        guard let app = availability.snapshot?.app else {
            scrubPosition = nil
            return
        }
        mediaLog.debug("seek → \(Int(target))s sur \(app.rawValue, privacy: .public)")
        scrubPosition = target
        Task {
            defer { scrubPosition = nil }
            do {
                try await MusicScriptingService().seek(app, to: target)
            } catch AppleScriptError.notAuthorized {
                availability = .permissionDenied(app: app)
                return
            } catch {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            await refresh()
        }
    }

    #if DEBUG
    /// Injecte un etat de lecture factice et coupe l'interrogation reelle. Sert
    /// a eprouver la carte sans dependre d'un lecteur lance ni d'une
    /// autorisation d'automatisation accordee.
    func injectDebugState(_ availability: MediaAvailability, artwork: NSImage? = nil) {
        stop()
        self.availability = availability
        self.artwork = artwork
    }
    #endif

    /// Relance apres un refus d'autorisation. Le systeme ne represente pas le
    /// dialogue une fois la reponse enregistree : si l'utilisateur a refuse, il
    /// faut passer par Reglages Systeme — d'ou le message porte par l'UI.
    func retryAuthorization() {
        Task { await refresh() }
    }
}
