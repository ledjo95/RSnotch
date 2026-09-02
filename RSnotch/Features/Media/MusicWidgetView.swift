import SwiftUI

// MARK: - MusicWidgetView
//
// Carte « lecture en cours ». Elle ne connait qu'un NowPlayingSnapshot : d'ou
// il vient — Music.app ou Spotify — ne change que le libelle et la presence du
// bouton « aimer ».
//
// La pochette occupe TOUT le fond de la carte. Le texte et les commandes se
// posent dessus, protégés par un voile degrade — une pochette claire rendrait
// sinon le titre illisible. Les commandes restent en verre, conformement aux
// recommandations Apple : le verre habille ce qui flotte au-dessus du contenu.
//
// POCHETTES ANIMEES : Apple Music en propose pour certains albums, mais ne les
// expose que dans son propre client — aucun dictionnaire de scripting, aucune
// API publique. Plutot que de dependre d'un symbole prive, la pochette statique
// respire tres legerement pendant la lecture. C'est un repli assume, pas une
// imitation, et il est documente dans les Reglages.

struct MusicWidgetView: View {

    @Bindable var model: NowPlayingViewModel
    let size: WidgetSize


    var body: some View {
        Group {
            switch model.availability {
            case .ready(let snapshot):
                if let track = snapshot.track {
                    player(snapshot, track)
                } else {
                    MediaNoticeView(
                        symbolName: "pause.circle",
                        title: "Rien en lecture",
                        detail: snapshot.app.displayName
                    )
                    .padding(12)
                }
            case .idle, .noPlayerRunning:
                MediaNoticeView(
                    symbolName: "music.note",
                    title: "Aucun lecteur",
                    detail: "Ouvrir Musique ou Spotify."
                )
                .padding(12)
            case .permissionDenied(let app):
                permissionNotice(app).padding(12)
            case .failed(let reason):
                MediaNoticeView(symbolName: "exclamationmark.triangle", title: "Indisponible", detail: reason)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(Theme.Motion.morph, value: model.availability)
    }

    // MARK: Lecteur

    private func player(_ snapshot: NowPlayingSnapshot, _ track: NowPlayingTrack) -> some View {
        // La pochette passe en `background` et NON en calque frere dans un
        // ZStack : une image `.aspectRatio(.fill)` propose sa taille intrinseque
        // et faisait grandir la carte — donc tout le panneau — bien au-dela des
        // 150 pt de la rangee. Un `background` se cale sur la vue principale et
        // ne participe jamais au calcul de taille.
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.app.supportsLoving {
                HStack {
                    Spacer(minLength: 0)
                    GlassRoundButton(
                        symbolName: track.isLoved ? "heart.fill" : "heart",
                        label: track.isLoved ? "Retirer des favoris" : "Ajouter aux favoris",
                        side: 22
                    ) { model.toggleLoved() }
                    .foregroundStyle(track.isLoved ? Theme.Palette.signal : .white)
                }
            }

            Spacer(minLength: 0)

            // Le titre ouvre le lecteur : c'est le geste attendu quand on veut
            // « voir » le morceau en entier.
            Button { model.openPlayer() } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title.isEmpty ? "Titre inconnu" : track.title)
                        .font(Theme.Typography.body(12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.frost)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(Theme.Typography.body(10))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir \(snapshot.app.displayName)")
            .accessibilityLabel("\(track.title), \(track.artist). Ouvrir \(snapshot.app.displayName)")

            ScrubBar(model: model, snapshot: snapshot, duration: track.duration)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                GlassRoundButton(symbolName: "backward.fill", label: "Morceau précédent", side: 24) {
                    model.previousTrack()
                }
                GlassRoundButton(
                    symbolName: snapshot.state.isPlaying ? "pause.fill" : "play.fill",
                    label: snapshot.state.isPlaying ? "Mettre en pause" : "Lire",
                    isAccented: true,
                    side: 28
                ) { model.togglePlayPause() }
                GlassRoundButton(symbolName: "forward.fill", label: "Morceau suivant", side: 24) {
                    model.nextTrack()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                ArtworkBackground(image: model.artwork, isBreathing: snapshot.state.isPlaying)
                scrim
            }
        }
        // Toute la carte ouvre le lecteur — pas seulement le titre. Les
        // boutons (coeur, lecture, barre de progression) captent leur propre
        // tap en priorite : seule la pochette et les zones vides retombent
        // ici. `contentShape` est necessaire car les `Spacer` ne dessinent
        // rien et ne repondraient sinon a aucun geste.
        .contentShape(Rectangle())
        .onTapGesture { model.openPlayer() }
        .accessibilityElement(children: .contain)
    }

    /// Voile de lisibilite. Degrade plutot qu'un aplat : la pochette reste
    /// visible en haut, le texte reste lisible en dessous quelle que soit
    /// l'image.
    ///
    /// La montee est calee sur le TEXTE, pas sur la hauteur de la carte : le
    /// titre commence vers 55 % et doit deja reposer sur un fond opaque. Un
    /// dégrade regulier laissait le titre a ~30 % de voile, soit du blanc sur
    /// gris clair des que la pochette etait lumineuse.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.Palette.ink.opacity(0.05), location: 0.0),
                .init(color: Theme.Palette.ink.opacity(0.30), location: 0.30),
                .init(color: Theme.Palette.ink.opacity(0.86), location: 0.52),
                .init(color: Theme.Palette.ink.opacity(0.94), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: Autorisation

    private func permissionNotice(_ app: MediaApp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.ember)
            Text("Autorisation requise")
                .font(Theme.Typography.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.frost)
            Text("Réglages Système › Confidentialité › Automatisation › RSnotch › \(app.displayName).")
                .font(Theme.Typography.body(10))
                .foregroundStyle(Theme.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            GlassActionButton(title: "Réessayer", symbolName: "arrow.clockwise") {
                model.retryAuthorization()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ArtworkBackground
//
// Pochette en fond plein cadre. Sans pochette, un aplat sombre porte une note
// discrete : un cadre vide donnerait l'impression d'un widget casse.

private struct ArtworkBackground: View {
    let image: NSImage?
    let isBreathing: Bool

    @State private var isInhaled = false
    /// La respiration est un mouvement continu : « Reduire les animations »
    /// l'eteint. La pochette reste alors posee a son facteur de repos.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    // La respiration ne doit jamais decouvrir un bord : le
                    // facteur de repos est deja legerement superieur a 1.
                    .scaleEffect(reduceMotion ? 1.02 : (isInhaled ? 1.06 : 1.02))
                    .animation(
                        isBreathing && !reduceMotion
                            ? .easeInOut(duration: 3.2).repeatForever(autoreverses: true)
                            : .default,
                        value: isInhaled
                    )
            } else {
                Theme.Palette.slate.overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.12))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { isInhaled = isBreathing }
        .onChange(of: isBreathing) { _, playing in isInhaled = playing }
        .accessibilityHidden(true)
    }
}

// MARK: - ScrubBar
//
// La position n'est pas relevee a chaque seconde (chaque releve reveille le
// lecteur) : elle est extrapolee depuis l'horodatage du dernier releve, et la
// TimelineView ne fait qu'animer cette extrapolation.
//
// Le geste de glissement est deliberement pose EN DEHORS de la TimelineView.
// A l'interieur, il etait reconstruit toutes les 500 ms avec le reste du
// contenu, ce qui annulait tout glissement en cours : la barre paraissait
// inerte. Seuls le remplissage et les libelles dependent du temps.

private struct ScrubBar: View {

    @Bindable var model: NowPlayingViewModel
    let snapshot: NowPlayingSnapshot
    let duration: TimeInterval

    /// Hauteur de la cible de pointage. La bande ne fait que 3 pt : viser un
    /// trait de 3 pt a la souris est irrealiste.
    private let hitHeight: CGFloat = 16

    private var isScrubbing: Bool { model.scrubPosition != nil }

    var body: some View {
        Group {
            if duration <= 0 {
                unknownDuration
            } else {
                VStack(spacing: 3) {
                    bar
                    labels
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Position de lecture")
        .accessibilityValue(duration > 0 ? "\(Int(snapshot.position / duration * 100)) %" : "inconnue")
        // Permet de deplacer la lecture au clavier, sans souris.
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 15
            let current = snapshot.position(at: .now)
            let target = direction == .increment ? current + step : current - step
            model.seek(to: min(max(0, target), duration))
        }
    }

    // MARK: Bande

    private var bar: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.filament)

                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let progress = progress(at: context.date)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Palette.ember)
                            .frame(width: width * progress)
                        // Pastille : sans elle, rien n'indique que la bande se
                        // saisit. Elle grossit pendant le glissement.
                        Circle()
                            .fill(.white)
                            .frame(width: isScrubbing ? 11 : 7, height: isScrubbing ? 11 : 7)
                            .offset(x: width * progress - (isScrubbing ? 5.5 : 3.5))
                            .animation(Theme.Motion.morph, value: isScrubbing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(1, max(0, value.location.x / width))
                        let target = ratio * duration
                        if model.scrubPosition == nil {
                            model.beginScrub(at: target)
                        } else {
                            model.updateScrub(to: target)
                        }
                    }
                    .onEnded { _ in model.endScrub() }
            )
        }
        .frame(height: hitHeight)
    }

    // MARK: Libelles

    private var labels: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = model.scrubPosition ?? snapshot.position(at: context.date)
            HStack {
                Text(position.playbackLabel)
                    // Pendant le reglage, le temps vise passe en ambre : c'est
                    // le seul retour qui dit ou l'on va atterrir.
                    .foregroundStyle(isScrubbing ? Theme.Palette.ember : Theme.Palette.mist)
                Spacer(minLength: 0)
                Text(max(0, duration - position).playbackLabel)
                    .foregroundStyle(Theme.Palette.mist)
            }
            .font(Theme.Typography.data(9))
            .monospacedDigit()
        }
    }

    /// Duree inconnue : certaines pistes locales ne l'exposent pas. Afficher une
    /// barre vide et « 0:00 » restant ferait croire a une panne — seul le temps
    /// ecoule a du sens ici, et il n'y a rien a regler.
    private var unknownDuration: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack {
                Text(snapshot.position(at: context.date).playbackLabel)
                Spacer(minLength: 0)
                Text("durée inconnue")
            }
            .font(Theme.Typography.data(9))
            .foregroundStyle(Theme.Palette.mist)
            .monospacedDigit()
            .frame(height: hitHeight + 3 + 11, alignment: .center)
        }
    }

    private func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let position = model.scrubPosition ?? snapshot.position(at: date)
        return min(1, max(0, position / duration))
    }
}

// MARK: - MediaNoticeView
/// Etat vide. Un carre noir donnerait l'impression d'un widget casse.
private struct MediaNoticeView: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        // Bloc CENTRE, et non ecartele haut/bas par un `Spacer`. Sur une carte
        // de 470 pt, l'ancienne disposition — glyphe colle en haut a gauche,
        // texte en bas — creusait un vide au milieu qui donnait la carte pour
        // cassee plutot que pour vide.
        VStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.Palette.wellFill))
                .overlay(Circle().strokeBorder(Theme.Palette.innerRim, lineWidth: 0.75))

            VStack(spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body(12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.frost)
                Text(detail)
                    .font(Theme.Typography.body(10))
                    .foregroundStyle(Theme.Palette.mist)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Formatage
extension TimeInterval {
    /// « 3:42 ». Les heures n'apparaissent que si le morceau les depasse.
    var playbackLabel: String {
        let total = Int(rounded())
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
