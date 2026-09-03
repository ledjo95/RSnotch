import SwiftUI

// MARK: - TimerTabView
//
// Onglet minuteur : la regle occupe toute la largeur, la ligne du bas porte la
// valeur, les presets et l'action. Pendant un decompte la regle se desactive au
// lieu de disparaitre — l'utilisateur garde sous les yeux la duree qu'il a
// choisie, et le panneau ne change pas de gabarit en cours de route.

struct TimerTabView: View {

    @Bindable var timer: TimerService

    @Environment(\.notchOpenLock) private var lockOpen

    @State private var showingPomodoroSettings = false
    /// Mode choisi dans le Picker, distinct de `timer.mode` : ce dernier ne
    /// bascule vraiment qu'au moment de `startPomodoro()`/`exitPomodoro()`
    /// (§ TimerService), pas au simple choix dans l'UI — un cycle Pomodoro en
    /// cours ne doit pas etre interrompu par un effet de bord du Picker. Cet
    /// etat local pilote donc l'affichage AVANT le premier « Demarrer ».
    @State private var selectedMode: TimerMode = .simple

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { timer.selectedMinutes },
            set: { timer.setDuration(minutes: $0) }
        )
    }

    private var isCounting: Bool {
        timer.state == .running || timer.state == .paused
    }

    /// Une fois un cycle Pomodoro reellement demarre, `timer.mode` fait foi
    /// (source de verite partagee avec le widget de la page d'accueil). Au
    /// repos, avant tout demarrage, `selectedMode` — purement local a cette
    /// vue — pilote l'affichage : `timer.mode` ne bascule qu'a `startPomodoro()`.
    private var displayedMode: TimerMode {
        isCounting || timer.state == .finished ? timer.mode : selectedMode
    }

    var body: some View {
        VStack(spacing: Theme.Metrics.contentSpacing) {
            if !isCounting {
                modePicker
            }
            if displayedMode == .pomodoro {
                pomodoroHeader
            }
            // La regle graduee edite `selectedDuration`, que `startPomodoro()`
            // ecrase de toute facon avec `pomodoroWorkMinutes` — la montrer en
            // Pomodoro laisserait croire qu'elle regle la duree du cycle,
            // alors que c'est la feuille de reglages (§ pomodoroHeader) qui
            // le fait. Masquee au lieu de desactivee : une regle visible mais
            // inerte serait plus deroutante qu'absente.
            if displayedMode == .simple {
                TickRuler(
                    minutes: minutesBinding,
                    range: TimerService.minimumMinutes...TimerService.maximumMinutes,
                    isEnabled: !isCounting
                )
            }
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingPomodoroSettings) {
            PomodoroSettingsSheet(timer: timer)
        }
        // La feuille s'affiche HORS de la coquille (sa propre NSWindow,
        // comme le sous-panneau de dossier § AppsWidgetView) : y amener la
        // souris fait sortir le pointeur de la forme du panneau, qui se
        // repliait 120 ms plus tard en emportant la feuille avec lui.
        .onChange(of: showingPomodoroSettings) { _, isShowing in
            lockOpen(isShowing)
        }
    }

    // MARK: Mode

    /// Visible seulement au repos, meme regle que la regle graduee : changer
    /// de mode en cours de decompte rendrait l'affichage incoherent.
    private var modePicker: some View {
        Picker("Mode", selection: modeBinding) {
            Text("Simple").tag(TimerMode.simple)
            Text("Pomodoro").tag(TimerMode.pomodoro)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var modeBinding: Binding<TimerMode> {
        Binding(
            get: { selectedMode },
            set: { newMode in
                selectedMode = newMode
                // Le passage a .pomodoro ne demarre rien : il attend
                // « Demarrer », qui appelle `startPomodoro()`. Revenir a
                // .simple alors qu'un cycle tournait deja (`timer.mode`) le
                // sort explicitement, plutot que de laisser `timer.mode` et
                // `selectedMode` diverger silencieusement.
                if newMode == .simple, timer.mode == .pomodoro {
                    timer.exitPomodoro()
                }
            }
        )
    }

    private var pomodoroHeader: some View {
        HStack {
            Text(timer.pomodoroPhase.label)
                .font(Theme.Typography.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.ember)
            Spacer(minLength: 0)
            Text("\(timer.completedWorkSessions) / \(timer.sessionsBeforeLongBreak)")
                .font(Theme.Typography.body(11))
                .foregroundStyle(Theme.Palette.mist)
                .monospacedDigit()
            // Desactive pendant un decompte, comme la regle graduee : changer
            // les durees de phase en cours de cycle rendrait le decompte
            // affiche incoherent avec le reglage.
            Button {
                showingPomodoroSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.mist)
            }
            .buttonStyle(.plain)
            .disabled(isCounting)
            .accessibilityLabel("Réglages du Pomodoro")
        }
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

            if !isCounting, displayedMode == .simple {
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
                withAnimation(Theme.Motion.morph) {
                    selectedMode == .pomodoro ? timer.startPomodoro() : timer.start()
                }
            }
        case .running:
            HStack(spacing: 6) {
                if isOnBreak {
                    GlassRoundButton(symbolName: "forward.fill", label: "Reprendre maintenant") {
                        withAnimation(Theme.Motion.morph) { timer.skipBreak() }
                    }
                }
                GlassRoundButton(
                    symbolName: "pause.fill",
                    label: "Mettre en pause",
                    isAccented: true
                ) { withAnimation(Theme.Motion.morph) { timer.pause() } }
                GlassRoundButton(symbolName: "xmark", label: "Arrêter") {
                    withAnimation(Theme.Motion.morph) { stopOrExit() }
                }
            }
        case .paused:
            HStack(spacing: 6) {
                if isOnBreak {
                    GlassRoundButton(symbolName: "forward.fill", label: "Reprendre maintenant") {
                        withAnimation(Theme.Motion.morph) { timer.skipBreak() }
                    }
                }
                GlassRoundButton(
                    symbolName: "play.fill",
                    label: "Reprendre",
                    isAccented: true
                ) { withAnimation(Theme.Motion.morph) { timer.start() } }
                GlassRoundButton(symbolName: "xmark", label: "Arrêter") {
                    withAnimation(Theme.Motion.morph) { stopOrExit() }
                }
            }
        }
    }

    private var isOnBreak: Bool {
        timer.mode == .pomodoro && timer.pomodoroPhase != .work
    }

    /// « Arrêter » en Pomodoro sort du cycle plutot que de seulement couper
    /// le decompte courant : sinon la prochaine reprise repartirait au
    /// milieu du cycle au lieu d'en sortir vraiment.
    private func stopOrExit() {
        timer.mode == .pomodoro ? timer.exitPomodoro() : timer.stop()
    }

    /// Au repos en Pomodoro, avant tout demarrage, `timer.selectedDuration`
    /// peut encore porter la duree du mode Simple (rien ne l'a mis a jour
    /// tant que `startPomodoro()` n'a pas tourne) — afficher la duree de
    /// travail Pomodoro directement evite de montrer un temps trompeur.
    private var displayedTime: String {
        guard !isCounting, timer.state != .finished else { return timer.remaining.countdownLabel }
        guard selectedMode == .pomodoro else { return timer.selectedDuration.countdownLabel }
        return Duration.seconds(timer.pomodoroWorkMinutes * 60).countdownLabel
    }
}
