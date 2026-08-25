import Foundation

// MARK: - MediaApp
/// Les deux lecteurs pilotables sans API privee. Chacun publie un dictionnaire
/// de scripting public : celui d'Apple pour Music.app, celui maintenu par
/// Spotify pour son client.
enum MediaApp: String, CaseIterable, Identifiable, Sendable {
    case music
    case spotify

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .music: "Musique"
        case .spotify: "Spotify"
        }
    }

    /// Notification distribuee publique emise a chaque changement de lecture.
    /// Elle sert de declencheur : sans elle, il faudrait interroger le lecteur
    /// en boucle serree pour voir arriver le morceau suivant.
    var playerInfoNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    /// Music.app expose `loved` / `favorited`. Le dictionnaire Spotify n'a
    /// aucun equivalent : le bouton doit disparaitre plutot qu'echouer.
    var supportsLoving: Bool { self == .music }
}

// MARK: - PlaybackState
enum PlaybackState: String, Sendable, Equatable {
    case stopped
    case playing
    case paused

    var isPlaying: Bool { self == .playing }

    /// Music.app ne se limite pas a trois valeurs : il rend aussi
    /// « fast forwarding » et « rewinding ». Les traiter comme un arret
    /// figerait la barre de progression pendant une avance rapide.
    init(scriptValue: String) {
        switch scriptValue {
        case "playing", "fast forwarding", "rewinding": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

// MARK: - NowPlayingTrack
struct NowPlayingTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let isLoved: Bool
    /// Spotify ne fournit sa pochette que par URL distante ; Music.app rend les
    /// octets directement (voir `MusicScriptingService.artwork`).
    let artworkURL: URL?

    /// Signature d'identite du morceau. Le dictionnaire de scripting n'expose
    /// pas d'identifiant stable commun aux deux lecteurs : le triplet suffit a
    /// detecter un changement de piste sans jamais se tromper de sens.
    var signature: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }
}

// MARK: - NowPlayingSnapshot
struct NowPlayingSnapshot: Equatable, Sendable {
    let app: MediaApp
    let state: PlaybackState
    let track: NowPlayingTrack?
    /// Position au moment de la capture. L'UI l'extrapole entre deux releves
    /// plutot que d'interroger le lecteur chaque seconde.
    let position: TimeInterval
    let capturedAt: Date

    /// Position estimee maintenant, bornee a la duree du morceau.
    func position(at date: Date) -> TimeInterval {
        guard state.isPlaying else { return position }
        let elapsed = date.timeIntervalSince(capturedAt)
        let raw = position + max(0, elapsed)
        guard let duration = track?.duration, duration > 0 else { return raw }
        return min(raw, duration)
    }
}

// MARK: - MediaAvailability
/// Un lecteur peut manquer a l'appel pour des raisons qui appellent chacune une
/// reponse differente de l'utilisateur : lancer l'app, accorder une permission,
/// ou rien du tout. Un `Error` nu ne porterait pas cette distinction.
enum MediaAvailability: Equatable, Sendable {
    case idle
    /// Ni Music.app ni Spotify ne tournent.
    case noPlayerRunning
    /// L'autorisation Apple Events n'a jamais ete demandee, ou a ete refusee.
    /// `MusicScriptingService` ne peut pas distinguer les deux de facon fiable :
    /// l'UI propose donc toujours de reessayer, et explique ou l'accorder.
    case permissionDenied(app: MediaApp)
    case failed(String)
    case ready(NowPlayingSnapshot)

    var snapshot: NowPlayingSnapshot? {
        if case .ready(let snapshot) = self { return snapshot }
        return nil
    }
}
