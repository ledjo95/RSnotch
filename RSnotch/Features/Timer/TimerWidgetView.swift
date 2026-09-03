import SwiftUI

// MARK: - TimerWidgetView
//
// Carte du minuteur dans la rangee de widgets. Elle ne sert qu'a suivre un
// decompte en cours : le reglage se fait dans l'onglet dedie, ou la regle a la
// place de s'etendre. Au repos, la carte renvoie vers cet onglet plutot que de
// proposer un reglage a l'etroit.
//
// Le temps restant se lit deux fois : en chiffres, et par le liseré ambre qui
// fait le tour de la carte et se retracte a mesure. Une seule audace visuelle,
// alignee sur le filament du panneau, et rien d'autre n'est colore ici.

struct TimerWidgetView: View {

    @Bindable var timer: TimerService
    /// Bascule vers l'onglet minuteur.
    let openTimerTab: () -> Void

    private var isCounting: Bool {
        timer.state == .running || timer.state == .paused
    }

    /// Le liseré ne se trace que pendant un decompte. Au repos, un tour complet
    /// laisserait croire qu'un minuteur tourne.
    private var ringProgress: Double {
        isCounting ? timer.progress : 0
    }

    var body: some View {
        // Le libelle est ancre en haut, le reste forme un BLOC CENTRE. Deux
        // `Spacer` egaux poussaient auparavant la valeur et les commandes
        // chacune vers un bord : sur une carte haute de 188 pt, le cadran et sa
        // commande se retrouvaient sans rapport visible l'un avec l'autre.
        VStack(spacing: 6) {
            Text(timer.mode == .pomodoro ? timer.pomodoroPhase.label : "Minuteur")
                .engraved()

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                // A l'arret, la carte montre la duree reglee ; des qu'un
                // decompte a commence — y compris une fois termine — elle
                // montre le temps restant, sinon la fin du minuteur
                // reafficherait la duree de depart et donnerait l'impression
                // qu'il n'a jamais tourne.
                Text(timer.state == .idle
                     ? timer.selectedDuration.countdownLabel
                     : timer.remaining.countdownLabel)
                    .font(Theme.Typography.display(46, weight: .bold))
                    .foregroundStyle(timer.state == .finished
                                     ? Theme.Palette.signal
                                     : Theme.Palette.ember)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                controls

                if timer.mode == .pomodoro {
                    Text("\(timer.completedWorkSessions) / \(timer.sessionsBeforeLongBreak)")
                        .font(Theme.Typography.body(9))
                        .foregroundStyle(Theme.Palette.mist)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        // Le liseré est pose APRES le padding : il epouse le bord de la carte,
        // pas celui du contenu.
        .overlay(progressRing)
        .contentShape(Rectangle())
        .onTapGesture { if !isCounting { openTimerTab() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Minuteur")
        .accessibilityValue(timer.remaining.countdownLabel)
    }

    // MARK: Liseré de progression

    @ViewBuilder
    private var progressRing: some View {
        // Inseré de la demi-epaisseur du trait : centre sur le bord, la moitie
        // du liseré tomberait hors de la carte et serait rognee.
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius,
                                     style: .continuous)
            .inset(by: 1.5)
        ZStack {
            // Rail : le tour complet, tres discret, pour que le trait ambre se
            // lise comme une portion d'un tout et non comme un accident.
            shape.stroke(Theme.Palette.filament, lineWidth: 2)
                .opacity(isCounting ? 1 : 0)

            shape
                .trim(from: 0, to: ringProgress)
                .stroke(
                    timer.state == .finished ? Theme.Palette.signal : Theme.Palette.ember,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                // Pas de rotation pour choisir le point de depart : elle ferait
                // pivoter le rectangle entier, pas seulement l'origine du trace.
                // `trim` part deja du haut a gauche et tourne dans le sens des
                // aiguilles, ce qui est l'ordre de lecture attendu.
                .animation(.linear(duration: 0.25), value: ringProgress)
        }
        .allowsHitTesting(false)
    }

    // MARK: Commandes

    @ViewBuilder
    private var controls: some View {
        switch timer.state {
        case .running:
            HStack(spacing: 8) {
                GlassRoundButton(symbolName: "pause.fill", label: "Mettre en pause",
                                 isAccented: true, side: 28) {
                    withAnimation(Theme.Motion.morph) { timer.pause() }
                }
                GlassRoundButton(symbolName: "xmark", label: "Arrêter", side: 28) {
                    withAnimation(Theme.Motion.morph) { timer.stop() }
                }
            }
        case .paused:
            HStack(spacing: 8) {
                GlassRoundButton(symbolName: "play.fill", label: "Reprendre",
                                 isAccented: true, side: 28) {
                    withAnimation(Theme.Motion.morph) { timer.start() }
                }
                GlassRoundButton(symbolName: "xmark", label: "Arrêter", side: 28) {
                    withAnimation(Theme.Motion.morph) { timer.stop() }
                }
            }
        case .finished:
            // Tant que ca sonne, la seule action utile est de faire taire :
            // elle passe donc en bouton accentue, et « Terminé » suffit sinon.
            if timer.isRinging {
                HStack(spacing: 8) {
                    GlassRoundButton(symbolName: "bell.slash.fill", label: "Couper la sonnerie",
                                     isAccented: true, side: 28) {
                        withAnimation(Theme.Motion.morph) { timer.silence() }
                    }
                    GlassRoundButton(symbolName: "xmark", label: "Réinitialiser", side: 28) {
                        withAnimation(Theme.Motion.morph) { timer.stop() }
                    }
                }
            } else {
                Text("Terminé")
                    .font(Theme.Typography.body(12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.signal)
            }
        case .idle:
            Text("Toucher pour régler")
                .font(Theme.Typography.body(11))
                .foregroundStyle(Theme.Palette.mist)
        }
    }
}
