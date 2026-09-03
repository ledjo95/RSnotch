import SwiftUI

// MARK: - PomodoroSettingsSheet
//
// Durees des trois phases et intervalle de pause longue. Les sources sur la
// technique s'accordent sur une plage large plutot qu'un chiffre fige (15 a
// 50 min de travail selon la difficulte de la tache, pause longue toutes les
// 2 a 6 sessions selon la duree retenue) — d'ou des `Stepper` sur une plage,
// pas un champ libre qui laisserait entrer des valeurs absurdes.

struct PomodoroSettingsSheet: View {

    @Bindable var timer: TimerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Réglages du Pomodoro")
                .font(.headline)

            durationRow(
                title: "Travail",
                minutes: $timer.pomodoroWorkMinutes,
                range: TimerService.pomodoroWorkRange
            )
            durationRow(
                title: "Pause courte",
                minutes: $timer.pomodoroShortBreakMinutes,
                range: TimerService.pomodoroShortBreakRange
            )
            durationRow(
                title: "Pause longue",
                minutes: $timer.pomodoroLongBreakMinutes,
                range: TimerService.pomodoroLongBreakRange
            )

            Stepper(
                "Pause longue toutes les \(timer.sessionsBeforeLongBreak) sessions",
                value: $timer.sessionsBeforeLongBreak,
                in: TimerService.sessionsBeforeLongBreakRange
            )

            Text("Les changements s’appliquent au prochain cycle démarré.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func durationRow(title: String, minutes: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: minutes, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(minutes.wrappedValue) min")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
