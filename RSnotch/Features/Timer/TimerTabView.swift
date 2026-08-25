import SwiftUI

// MARK: - TimerTabView
//
// Onglet minuteur : la regle occupe toute la largeur, la ligne du bas porte la
// valeur, les presets et l'action. Pendant un decompte la regle se desactive au
// lieu de disparaitre — l'utilisateur garde sous les yeux la duree qu'il a
// choisie, et le panneau ne change pas de gabarit en cours de route.

struct TimerTabView: View {

    @Bindable var timer: TimerService

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { timer.selectedMinutes },
            set: { timer.setDuration(minutes: $0) }
        )
    }

    private var isCounting: Bool {
        timer.state == .running || timer.state == .paused
    }

    var body: some View {
        VStack(spacing: Theme.Metrics.contentSpacing) {
            TickRuler(
                minutes: minutesBinding,
                range: TimerService.minimumMinutes...TimerService.maximumMinutes,
                isEnabled: !isCounting
            )
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Ligne de commande

    private var controls: some View {
        HStack(spacing: Theme.Metrics.contentSpacing) {
            Text(displayedTime)
                .font(Theme.Typography.display(34, weight: .semibold))
                // Un decompte arrive a terme doit se distinguer d'un minuteur
                // pret a partir : sans cela, les deux etats affichent la meme
                // duree et le meme bouton.
                .foregroundStyle(
                    timer.state == .finished ? Theme.Palette.signal : Theme.Palette.ember
                )
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: displayedTime)
                .accessibilityLabel(isCounting ? "Temps restant" : "Durée choisie")
                .accessibilityValue(displayedTime)

            if timer.state == .finished {
                Text("Terminé")
                    .font(Theme.Typography.body(12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.signal)
            }

            Spacer(minLength: 8)

            if !isCounting {
                presets
            }

            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presets: some View {
        HStack(spacing: 4) {
            ForEach(TimerService.presets, id: \.self) { preset in
                Button {
                    withAnimation(Theme.Motion.morph) {
                        timer.setDuration(minutes: preset)
                    }
                } label: {
                    Text("\(preset) min")
                        .font(Theme.Typography.body(10, weight: .medium))
                        .foregroundStyle(
                            timer.selectedMinutes == preset ? Theme.Palette.ink : Theme.Palette.mist
                        )
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(
                                timer.selectedMinutes == preset
                                    ? Color.white
                                    : Theme.Palette.slate.opacity(0.7)
                            )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset) minutes")
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch timer.state {
        case .idle, .finished:
            GlassActionButton(title: "Démarrer", symbolName: "play.fill") {
                withAnimation(Theme.Motion.morph) { timer.start() }
            }
        case .running:
            HStack(spacing: 6) {
                GlassRoundButton(
                    symbolName: "pause.fill",
                    label: "Mettre en pause",
                    isAccented: true
                ) { withAnimation(Theme.Motion.morph) { timer.pause() } }
                GlassRoundButton(symbolName: "xmark", label: "Arrêter") {
                    withAnimation(Theme.Motion.morph) { timer.stop() }
                }
            }
        case .paused:
            HStack(spacing: 6) {
                GlassRoundButton(
                    symbolName: "play.fill",
                    label: "Reprendre",
                    isAccented: true
                ) { withAnimation(Theme.Motion.morph) { timer.start() } }
                GlassRoundButton(symbolName: "xmark", label: "Arrêter") {
                    withAnimation(Theme.Motion.morph) { timer.stop() }
                }
            }
        }
    }

    private var displayedTime: String {
        isCounting ? timer.remaining.countdownLabel : timer.selectedDuration.countdownLabel
    }
}
