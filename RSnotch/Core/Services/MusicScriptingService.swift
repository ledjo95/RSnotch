import AppKit
import Foundation

// MARK: - MusicScriptingService
//
// Pont vers Music.app et Spotify.app par Apple Events.
//
// POURQUOI PAS MediaRemote : le framework qui alimente le « Now Playing » du
// systeme est prive. Il est interdit sur le Mac App Store et casserait a chaque
// mise a jour de macOS. Le dictionnaire de scripting, lui, est public, versionne
// et soumis au consentement de l'utilisateur — c'est la seule voie conforme.
//
// CE QUE CELA COUTE : l'app ne voit que Music.app et Spotify.app. Un morceau
// joue depuis Safari, VLC ou un autre client n'apparaitra pas. Limitation
// assumee et affichee dans les Reglages, pas contournee.
//
// ENTITLEMENT REQUIS : com.apple.security.automation.apple-events
// + cle Info.plist NSAppleEventsUsageDescription (texte du dialogue systeme).
//
// LIMITE DE TEMPS : chaque script est encadre d'un `with timeout`. Sans elle,
// un lecteur qui ne repond pas — Spotify bloque derriere un dialogue systeme,
// par exemple — fige la file serie POUR DE BON : plus aucun releve ne passe, et
// le widget reste vide sans rien signaler. AESend attend indefiniment par
// defaut ; `with timeout` est la seule facon publique de le borner.
//
// Les nombres traversent toujours la frontiere AppleScript en ENTIERS. Un reel
// converti en texte suit le separateur decimal du systeme : en francais,
// `242.5 as text` rend « 242,5 », que Swift ne sait pas relire. Arrondir a la
// seconde suffit largement a une barre de progression.

struct MusicScriptingService: Sendable {

    private let runner = AppleScriptRunner.shared

    /// Separateur de champs : unite ASCII 31, absent de tout titre reel.
    static let separator: Character = "\u{1F}"

    // MARK: Detection du lecteur

    /// Lecteur a interroger. Priorite a celui qui joue reellement ; a defaut,
    /// au premier lance. Interroger une app arretee la LANCERAIT — un
    /// `tell application` reveille sa cible — d'ou cette verification prealable
    /// via NSWorkspace, qui, elle, ne demande aucune permission.
    @MainActor
    static func runningPlayers() -> [MediaApp] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MediaApp.allCases.filter { running.contains($0.bundleIdentifier) }
    }

    // MARK: Releve

    func snapshot(for app: MediaApp) async throws -> NowPlayingSnapshot {
        let descriptor = try await runner.run(Self.stateScript(for: app))
        return Self.parseSnapshot(from: descriptor.stringValue ?? "", app: app, capturedAt: Date())
    }

    /// Decode la sortie brute d'un script d'etat en instantane.
    ///
    /// Extrait de `snapshot(for:)` — et rendu pur — pour etre eprouve sans
    /// lancer d'AppleScript : c'est la logique la plus fragile du pont (huit
    /// champs, un separateur de controle, des entiers a relire), et celle ou
    /// une derive du dictionnaire de scripting passerait inapercue.
    static func parseSnapshot(
        from raw: String, app: MediaApp, capturedAt: Date
    ) -> NowPlayingSnapshot {
        let fields = raw.split(separator: Self.separator, omittingEmptySubsequences: false)
                        .map(String.init)

        // Les deux scripts rendent huit champs, ou le seul mot « stopped ».
        // Toute autre forme signale un dictionnaire de scripting different de
        // celui attendu : mieux vaut un etat vide qu'une lecture de travers.
        guard fields.count == 8 else {
            return NowPlayingSnapshot(
                app: app, state: .stopped, track: nil, position: 0, capturedAt: capturedAt
            )
        }

        let state = PlaybackState(scriptValue: fields[0])
        let track = NowPlayingTrack(
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: TimeInterval(Int(fields[4]) ?? 0),
            isLoved: fields[6] == "1",
            artworkURL: fields[7].isEmpty ? nil : URL(string: fields[7])
        )
        return NowPlayingSnapshot(
            app: app,
            state: state,
            track: track,
            position: TimeInterval(Int(fields[5]) ?? 0),
            capturedAt: capturedAt
        )
    }

    /// Pochette. Music.app rend les octets bruts ; Spotify ne publie qu'une URL
    /// distante, telechargee par l'appelant (voir NowPlayingViewModel).
    func artwork(for app: MediaApp) async throws -> NSImage? {
        guard app == .music else { return nil }
        let descriptor = try await runner.run(Self.artworkScript)
        guard let data = descriptor.data as Data?, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    // MARK: Commandes

    func togglePlayPause(_ app: MediaApp) async throws {
        try await runner.perform(Self.command("playpause", on: app))
    }

    func nextTrack(_ app: MediaApp) async throws {
        try await runner.perform(Self.command("next track", on: app))
    }

    func previousTrack(_ app: MediaApp) async throws {
        try await runner.perform(Self.command("previous track", on: app))
    }

    func seek(_ app: MediaApp, to seconds: TimeInterval) async throws {
        let value = max(0, Int(seconds.rounded()))
        // `cacheable: false` : la position varie a chaque appel, donc la
        // source varie aussi (§ note d'AppleScriptRunner). La laisser passer
        // par le cache y ajouterait une entree neuve, jamais reutilisee, a
        // chaque seconde ciblee — un cache qui grandit sans fin sur toute une
        // session, pour un gain de reutilisation nul.
        try await runner.perform(
            Self.command("set player position to \(value)", on: app),
            cacheable: false
        )
    }

    /// Aime / n'aime plus. Music.app a renomme `loved` en `favorited` ; les deux
    /// noms cohabitent selon la version, d'ou la double tentative.
    func setLoved(_ isLoved: Bool, on app: MediaApp) async throws {
        guard app.supportsLoving else { return }
        let flag = isLoved ? "true" : "false"
        try await runner.perform("""
        with timeout of 3 seconds
            tell application id "com.apple.Music"
                try
                    set favorited of current track to \(flag)
                on error
                    set loved of current track to \(flag)
                end try
            end tell
        end timeout
        """)
    }

    // MARK: Sources

    private static func command(_ body: String, on app: MediaApp) -> String {
        """
        with timeout of 3 seconds
            tell application id "\(app.bundleIdentifier)"
                \(body)
            end tell
        end timeout
        """
    }

    /// Un seul aller-retour rapporte tout l'etat. Sept requetes separees
    /// multiplieraient le cout ET pourraient decrire deux morceaux differents
    /// si la piste change au milieu.
    private static func stateScript(for app: MediaApp) -> String {
        switch app {
        case .music: musicStateScript
        case .spotify: spotifyStateScript
        }
    }

    // Chaque champ est isole dans son propre `try`. Une piste peut tres bien
    // rendre `missing value` sur n'importe quelle propriete — un fichier local
    // dont Music n'a pas encore calcule la duree, par exemple. Sans cet
    // isolement, `round (duration of trk)` fait echouer le RELEVE ENTIER en
    // -1700, et le widget reste vide alors que la lecture est en cours.
    private static let musicStateScript = """
    with timeout of 3 seconds
        tell application id "com.apple.Music"
            set sep to (character id 31)
            set playState to (player state as text)
            if playState is "stopped" then return "stopped"
            try
                set trk to current track
            on error
                return "stopped"
            end try
            set tName to ""
            try
                set tName to (name of trk as text)
            end try
            set tArtist to ""
            try
                set tArtist to (artist of trk as text)
            end try
            set tAlbum to ""
            try
                set tAlbum to (album of trk as text)
            end try
            set tDur to 0
            try
                set rawDur to duration of trk
                set tDur to (round rawDur)
            end try
            set pos to 0
            try
                -- La valeur passe par une variable AVANT d'etre arrondie.
                -- `round (player position)` echoue chez les deux lecteurs
                -- (« impossible de convertir player position en type real ») :
                -- l'expression est evaluee dans la portee de l'application
                -- cible, qui ne sait pas la coercer. Liee d'abord, elle est
                -- deja un reel cote AppleScript.
                set rawPos to player position
                set pos to (round rawPos)
            end try
            set lv to "0"
            try
                if favorited of trk is true then set lv to "1"
            on error
                try
                    if loved of trk is true then set lv to "1"
                end try
            end try
            return playState & sep & tName & sep & tArtist & sep & tAlbum ¬
                & sep & (tDur as text) & sep & (pos as text) & sep & lv & sep & ""
        end tell
    end timeout
    """

    // Spotify exprime la duree en MILLISECONDES et la position en secondes.
    // La conversion se fait ici pour que le reste de l'app ne connaisse qu'une
    // seule unite.
    private static let spotifyStateScript = """
    with timeout of 3 seconds
        tell application id "com.spotify.client"
            set sep to (character id 31)
            set playState to (player state as text)
            if playState is "stopped" then return "stopped"
            try
                set trk to current track
            on error
                return "stopped"
            end try
            set tName to ""
            try
                set tName to (name of trk as text)
            end try
            set tArtist to ""
            try
                set tArtist to (artist of trk as text)
            end try
            set tAlbum to ""
            try
                set tAlbum to (album of trk as text)
            end try
            set tDur to 0
            try
                set rawDur to (duration of trk) / 1000
                set tDur to (round rawDur)
            end try
            set pos to 0
            try
                -- La valeur passe par une variable AVANT d'etre arrondie.
                -- `round (player position)` echoue chez les deux lecteurs
                -- (« impossible de convertir player position en type real ») :
                -- l'expression est evaluee dans la portee de l'application
                -- cible, qui ne sait pas la coercer. Liee d'abord, elle est
                -- deja un reel cote AppleScript.
                set rawPos to player position
                set pos to (round rawPos)
            end try
            set art to ""
            try
                set art to (artwork url of trk as text)
            end try
            return playState & sep & tName & sep & tArtist & sep & tAlbum ¬
                & sep & (tDur as text) & sep & (pos as text) & sep & "0" & sep & art
        end tell
    end timeout
    """

    private static let artworkScript = """
    with timeout of 5 seconds
        tell application id "com.apple.Music"
            try
                if (count of artworks of current track) is 0 then return ""
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
    end timeout
    """
}
