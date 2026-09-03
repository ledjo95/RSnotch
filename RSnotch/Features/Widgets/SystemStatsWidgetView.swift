import SwiftUI

// MARK: - SystemStatsWidgetView
//
// Aperçu compact de `SystemStatsTabView` sur la page d'accueil : CPU et
// mémoire en `.small`, disque en plus en `.medium`. Un tap ouvre l'onglet
// complet, comme `TimerWidgetView` renvoie vers l'onglet Minuteur.
//
// Instance de `SystemStatsService` PROPRE au widget, distincte de celle que
// possède `ExpandedPanelView` pour l'onglet Stats : chaque consommateur
// démarre/arrête son propre relevé selon sa propre visibilité, pour ne
// jamais sonder le CPU depuis un panneau fermé ou un onglet non affiché.

struct SystemStatsWidgetView: View {

    @State private var stats = SystemStatsService()
    let size: WidgetSize
    /// Bascule vers l'onglet Statistiques.
    let openStatsTab: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Statistiques")
                .engraved()

            Spacer(minLength: 0)

            if let snapshot = stats.snapshot {
                HStack(spacing: 10) {
                    row(title: "CPU", symbolName: "cpu",
                        fraction: snapshot.cpuUsage,
                        value: SystemStatsFormatting.percentLabel(snapshot.cpuUsage))
                    row(title: "Mémoire", symbolName: "memorychip",
                        fraction: snapshot.memoryUsage,
                        value: SystemStatsFormatting.percentLabel(snapshot.memoryUsage))
                    if size == .medium {
                        row(title: "Disque", symbolName: "internaldrive",
                            fraction: snapshot.diskUsage,
                            value: SystemStatsFormatting.percentLabel(snapshot.diskUsage))
                    }
                }
            } else {
                Text("Lecture…")
                    .font(Theme.Typography.body(12))
                    .foregroundStyle(Theme.Palette.mist)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { openStatsTab() }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Statistiques système")
    }

    private func row(title: String, symbolName: String, fraction: Double, value: String) -> some View {
        VStack(spacing: 4) {
            CircularGauge(fraction: fraction, symbolName: symbolName)
                .frame(width: 32, height: 32)
            Text(value)
                .font(Theme.Typography.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.frost)
                .monospacedDigit()
            Text(title)
                .font(Theme.Typography.body(9))
                .foregroundStyle(Theme.Palette.mist)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) : \(value)")
    }
}
